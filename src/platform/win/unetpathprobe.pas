{
   Double Commander
   -------------------------------------------------------------------------
   Checks the availability of network paths without freezing the user
   interface.

   Accessing an unreachable network path (UNC path or mapped network drive)
   blocks the calling thread until the SMB timeout expires (20-45 seconds).
   Therefore network paths are not accessed from the main thread:
   - the panel changes to a network path at once, the file list is loaded
     in the background and an unreachable path is reported in the panel;
   - before accessing the share a quick TCP connect to the SMB ports of the
     host is tried, an unreachable host is detected in about two seconds;
   - unreachable shares are remembered for a while, so repeated checks
     (e.g. on panel activation) return immediately.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.
}

unit uNetPathProbe;

{$mode objfpc}{$H+}

interface

uses
  Classes;

{en
   Returns @true if Path is on a network share (UNC path or mapped
   network drive). Does not access the network.
}
function IsNetworkPath(const Path: String): Boolean;
{en
   Checks whether a network path is reachable. Blocks the caller,
   use it from a background thread only. Returns @true for local paths.
}
function NetPathReachable(const Path: String): Boolean;
{en
   Checks only whether the host of a network path is reachable (the share
   is not accessed, so a connection with credentials can still be made).
   Blocks the caller, use it from a background thread only.
}
function NetHostReachable(const Path: String): Boolean;
{en
   Error message of the last failed access to the network path,
   empty if the last access succeeded.
}
function NetPathError(const Path: String): String;
procedure NetSetPathError(const Path, Message: String);
{en
   Checks whether a file system entry exists without blocking. For network
   paths the last known state (or Default) is returned and a background
   check is started. The file views showing the path are updated when
   the check finishes.
}
function NetFileSystemEntryExists(const Path: String; Default: Boolean): Boolean;
{en
   Returns @true if Path is a local path or a network path which was found
   reachable recently. Otherwise starts a background check (see
   NetFileSystemEntryExists) and returns @false.
}
function NetPathAvailableNow(const Path: String): Boolean;
{en
   Forgets the cached state of the network share containing Path
   (e.g. after the network drive was connected).
}
procedure NetPathResetCache(const Path: String);
{en
   Cancels the network checks and the synchronous I/O (e.g. listing an
   unreachable directory) running in Thread. The checks in Thread fail
   until it calls NetCancelReset.
}
procedure NetCancelThread(Thread: TThread);
{en
   Clears the cancelled state of the calling thread, call it before
   starting a new task in a reused thread.
}
procedure NetCancelReset;
{en
   Returns @true if the network checks of the calling thread were cancelled.
}
function NetCancelled: Boolean;

implementation

uses
  SysUtils, SyncObjs, Math, Windows, JwaWinNetWk, WinSock2,
  Generics.Collections, Forms, DCOSUtils, DCWindows, DCConvertEncoding,
  uFileView, fMain;

const
  // Positive results are trusted for this time
  POSITIVE_TTL = 10000;
  // Unreachable shares are remembered for this time
  NEGATIVE_TTL = 30000;
  // Loading a file list retries an unreachable share sooner
  NAVIGATE_NEGATIVE_TTL = 10000;
  // Timeout of the quick SMB port check
  CONNECT_TIMEOUT = 2000;
  // The port check looks for cancellation this often
  CANCEL_CHECK_INTERVAL = 100;

type
  // Unreachable: nothing, the share or the whole host
  TNetError = (neNone, neShare, neHost);

  TProbeEntry = record
    Exists: Boolean;
    Tick: QWord;      // when Exists was determined, 0 = never
    Pending: Boolean; // a background check is running
  end;

  TProbeCache = specialize TDictionary<UnicodeString, TProbeEntry>;
  TRootCache = specialize TDictionary<UnicodeString, QWord>;
  TErrorCache = specialize TDictionary<UnicodeString, String>;
  // Thread ID -> creation time of the thread (thread IDs are reused)
  TCancelSet = specialize TDictionary<TThreadID, QWord>;

  { TProbeThread }

  TProbeThread = class(TThread)
  private
    FPath: String;
    FKey: UnicodeString;
    FRoot: UnicodeString;
    FHost: UnicodeString;
  protected
    procedure Execute; override;
  public
    constructor Create(const APath: String; const AKey, ARoot, AHost: UnicodeString); reintroduce;
  end;

  { TProbeNotice }

  TProbeNotice = class
    Key: UnicodeString;
    procedure PathChecked(Data: PtrInt);
    procedure UpdateView(AFileView: TFileView; UserData: Pointer);
  end;

  PAddrInfoW = ^TAddrInfoW;
  TAddrInfoW = record
    ai_flags: Integer;
    ai_family: Integer;
    ai_socktype: Integer;
    ai_protocol: Integer;
    ai_addrlen: PtrUInt;
    ai_canonname: PWideChar;
    ai_addr: PSockAddr;
    ai_next: PAddrInfoW;
  end;

function GetAddrInfoW(pNodeName, pServiceName: PWideChar; pHints: PAddrInfoW;
  var ppResult: PAddrInfoW): Integer; stdcall; external 'ws2_32.dll';
procedure FreeAddrInfoW(pAddrInfo: PAddrInfoW); stdcall; external 'ws2_32.dll';
function CancelSynchronousIo(hThread: THandle): BOOL; stdcall; external 'kernel32.dll';

var
  FLock: SyncObjs.TCriticalSection = nil;
  FCache: TProbeCache = nil;
  FDeadRoots: TRootCache = nil;
  FErrors: TErrorCache = nil;
  FCancelled: TCancelSet = nil;
  FShutdown: Boolean = False;

function ThreadCreationTime(Thread: THandle): QWord;
var
  CreationTime, ExitTime, KernelTime, UserTime: TFileTime;
begin
  if GetThreadTimes(Thread, CreationTime, ExitTime, KernelTime, UserTime) then
    Result:= (QWord(CreationTime.dwHighDateTime) shl 32) or CreationTime.dwLowDateTime
  else
    Result:= 0;
end;

function NetCancelled: Boolean;
var
  Created: QWord;
begin
  FLock.Acquire;
  try
    Result:= Assigned(FCancelled) and FCancelled.TryGetValue(GetCurrentThreadId, Created) and
             (Created = ThreadCreationTime(GetCurrentThread));
  finally
    FLock.Release;
  end;
end;

function MakeKey(const Path: UnicodeString): UnicodeString;
begin
  Result:= WideUpperCase(Path);
  while (Length(Result) > 2) and (Result[Length(Result)] = PathDelim) do
    SetLength(Result, Length(Result) - 1);
end;

{en
   Returns @true if Path is a network path. Root is the share
   (\\HOST\SHARE) or the mapped drive (Z:), Host is the server name
   for UNC paths (for mapped drives it is resolved by the thread).
}
function GetNetworkRoot(const Path: String; out Root, Host: UnicodeString): Boolean;
var
  S: UnicodeString;
  I, J: Integer;
begin
  Root:= '';
  Host:= '';
  S:= CeUtf8ToUtf16(Path);
  if (Pos('\\?\UNC\', WideUpperCase(Copy(S, 1, 8))) = 1) then
    S:= '\\' + Copy(S, 9, MaxInt)
  else if (Pos('\\?\', S) = 1) then
    Delete(S, 1, 4);

  if (Length(S) > 2) and (S[1] = '\') and (S[2] = '\') then
  begin
    // Device paths (\\.\, \\?\)
    if (S[3] = '.') or (S[3] = '?') then Exit(False);
    I:= Pos('\', Copy(S, 3, MaxInt));
    if I = 0 then
    begin
      Host:= Copy(S, 3, MaxInt);
      Root:= S;
    end
    else begin
      I:= I + 2;
      Host:= Copy(S, 3, I - 3);
      J:= Pos('\', Copy(S, I + 1, MaxInt));
      if J = 0 then
        Root:= S
      else
        Root:= Copy(S, 1, I + J - 1);
    end;
    Root:= MakeKey(Root);
    Result:= (Host <> '');
  end
  else if (Length(S) >= 2) and (S[2] = ':') then
  begin
    Root:= WideUpperCase(Copy(S, 1, 2));
    Result:= (GetDriveTypeW(PWideChar(Root + '\')) = DRIVE_REMOTE);
  end
  else
    Result:= False;
end;

function GetNetError(Error: DWORD): TNetError;
begin
  case Error of
    ERROR_REM_NOT_LIST,
    ERROR_BAD_NETPATH,
    ERROR_SEM_TIMEOUT,
    ERROR_NETWORK_UNREACHABLE,
    ERROR_HOST_UNREACHABLE,
    ERROR_CONNECTION_REFUSED:
      Result:= neHost;
    ERROR_NETWORK_BUSY,
    ERROR_DEV_NOT_EXIST,
    ERROR_UNEXP_NET_ERR,
    ERROR_NETNAME_DELETED,
    ERROR_BAD_NET_NAME,
    ERROR_NO_NET_OR_BAD_PATH,
    ERROR_NO_NETWORK,
    ERROR_NOT_CONNECTED:
      Result:= neShare;
    else
      Result:= neNone;
  end;
end;

{en
   Hosts which are not accessed through SMB (RDP, WSL, virtual
   machine shared folders, WebDAV), the port check is not usable.
}
function CanCheckPort(const Host, Root: UnicodeString): Boolean;
var
  H: UnicodeString;
begin
  H:= WideLowerCase(Host);
  Result:= (H <> 'localhost') and (H <> 'tsclient') and
           (H <> 'vboxsvr') and (H <> 'vboxsrv') and (H <> 'vmware-host') and
           (H <> 'wsl.localhost') and (Pos('@', H) = 0) and (Pos('$', H) = 0) and
           (Pos('DAVWWWROOT', Root) = 0);
end;

{en
   Tries to connect to the SMB ports (445, 139) of the host.
   Known is @false if the result can not be determined
   (the name can not be resolved, loopback address, etc).
}
function IsLoopback(Addr: PAddrInfoW): Boolean;
const
  Loopback6: array[0..15] of Byte = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
begin
  case Addr^.ai_family of
    // sockaddr_in: family, port, address
    AF_INET: Result:= (PByte(Addr^.ai_addr)[4] = 127);
    // sockaddr_in6: family, port, flow info, address
    AF_INET6: Result:= CompareMem(PByte(Addr^.ai_addr) + 8, @Loopback6[0], 16);
    else Result:= False;
  end;
end;

function HostReachable(const Host: UnicodeString; out Known: Boolean): Boolean;
const
  Ports: array[0..1] of Word = (445, 139);
  MAX_SOCKETS = 8;
var
  I, Count: Integer;
  Port: Word;
  Mode: u_long;
  WSAData: TWSAData;
  Hints: TAddrInfoW;
  AddrList, Addr: PAddrInfoW;
  Sockets: array[0..MAX_SOCKETS - 1] of TSocket;
  Alive: array[0..MAX_SOCKETS - 1] of Boolean;
  Buffer: array[0..127] of Byte;
  WriteSet, ErrorSet: TFDSet;
  TimeVal: TTimeVal;
  StartTime, Elapsed: QWord;
begin
  Result:= False;
  Known:= False;
  if WSAStartup(MakeWord(2, 2), WSAData) <> 0 then Exit;
  try
    ZeroMemory(@Hints, SizeOf(Hints));
    Hints.ai_family:= AF_UNSPEC;
    Hints.ai_socktype:= SOCK_STREAM;
    Hints.ai_protocol:= IPPROTO_TCP;
    AddrList:= nil;
    if GetAddrInfoW(PWideChar(Host), nil, @Hints, AddrList) <> 0 then Exit;
    try
      // Loopback address: the share may be served by a local redirector
      Addr:= AddrList;
      while Assigned(Addr) do
      begin
        if IsLoopback(Addr) then Exit;
        Addr:= Addr^.ai_next;
      end;

      Count:= 0;
      Addr:= AddrList;
      while Assigned(Addr) and (Count < MAX_SOCKETS) do
      begin
        if (Addr^.ai_addrlen > SizeOf(Buffer)) then
        begin
          Addr:= Addr^.ai_next;
          Continue;
        end;
        for Port in Ports do
        begin
          if Count >= MAX_SOCKETS then Break;
          Sockets[Count]:= socket(Addr^.ai_family, SOCK_STREAM, IPPROTO_TCP);
          if Sockets[Count] = INVALID_SOCKET then Continue;
          Mode:= 1;
          ioctlsocket(Sockets[Count], LongInt(FIONBIO), Mode);
          Move(Addr^.ai_addr^, Buffer, Addr^.ai_addrlen);
          // sin_port and sin6_port have the same offset
          PSockAddrIn(@Buffer)^.sin_port:= htons(Port);
          if (connect(Sockets[Count], PSockAddr(@Buffer), Addr^.ai_addrlen) = 0) then
            Result:= True
          else if (WSAGetLastError <> WSAEWOULDBLOCK) then
          begin
            closesocket(Sockets[Count]);
            Continue;
          end;
          Alive[Count]:= True;
          Inc(Count);
        end;
        Addr:= Addr^.ai_next;
      end;
      if Count = 0 then Exit;

      Known:= True;
      StartTime:= GetTickCount64;
      while not Result do
      begin
        FD_ZERO(WriteSet);
        FD_ZERO(ErrorSet);
        for I:= 0 to Count - 1 do
          if Alive[I] then
          begin
            FD_SET(Sockets[I], WriteSet);
            FD_SET(Sockets[I], ErrorSet);
          end;
        if WriteSet.fd_count = 0 then Break;
        Elapsed:= GetTickCount64 - StartTime;
        if Elapsed >= CONNECT_TIMEOUT then Break;
        if NetCancelled then
        begin
          Known:= False;
          Break;
        end;
        Elapsed:= CONNECT_TIMEOUT - Elapsed;
        if Elapsed > CANCEL_CHECK_INTERVAL then Elapsed:= CANCEL_CHECK_INTERVAL;
        TimeVal.tv_sec:= 0;
        TimeVal.tv_usec:= Elapsed * 1000;
        I:= select(0, nil, @WriteSet, @ErrorSet, @TimeVal);
        if I < 0 then Break;
        if I = 0 then Continue;
        for I:= 0 to Count - 1 do
        begin
          if not Alive[I] then Continue;
          if FD_ISSET(Sockets[I], WriteSet) then
            Result:= True
          else if FD_ISSET(Sockets[I], ErrorSet) then
            Alive[I]:= False;
        end;
      end;

      for I:= 0 to Count - 1 do
        closesocket(Sockets[I]);
    finally
      FreeAddrInfoW(AddrList);
    end;
  finally
    WSACleanup;
  end;
end;

function HostKey(const Host: UnicodeString): UnicodeString;
begin
  Result:= '\\' + WideUpperCase(Host);
end;

{en
   Returns @true if the share or the whole host was found unreachable
   within TimeToLive.
}
function RootIsDead(const Root, Host: UnicodeString; TimeToLive: QWord): Boolean;
var
  Tick: QWord;
begin
  FLock.Acquire;
  try
    Result:= FDeadRoots.TryGetValue(Root, Tick) and (GetTickCount64 - Tick < TimeToLive);
    if (not Result) and (Host <> '') then
      Result:= FDeadRoots.TryGetValue(HostKey(Host), Tick) and (GetTickCount64 - Tick < TimeToLive);
  finally
    FLock.Release;
  end;
end;

procedure StoreResult(const Key, Root, Host: UnicodeString; Exists: Boolean;
                      NetError: TNetError; Background: Boolean);
var
  Entry: TProbeEntry;
begin
  if not FCache.TryGetValue(Key, Entry) then
    Entry.Pending:= False;
  if Background then Entry.Pending:= False;
  Entry.Exists:= Exists;
  Entry.Tick:= GetTickCount64;
  // Network paths visited during the session, keep the cache small anyway
  if FCache.Count > 4096 then FCache.Clear;
  FCache.AddOrSetValue(Key, Entry);

  case NetError of
    neNone:
      begin
        FDeadRoots.Remove(Root);
        if Host <> '' then FDeadRoots.Remove(HostKey(Host));
      end;
    neShare:
      FDeadRoots.AddOrSetValue(Root, GetTickCount64);
    neHost:
      begin
        FDeadRoots.AddOrSetValue(Root, GetTickCount64);
        if Host <> '' then FDeadRoots.AddOrSetValue(HostKey(Host), GetTickCount64);
      end;
  end;
end;

{en
   Checks the path and stores the result in the cache.
   Blocks the caller until the check finishes.
}
function ProbePath(const Path: String; const Key, Root: UnicodeString;
                   Host: UnicodeString; Background: Boolean): Boolean;
var
  Attr: DWORD;
  Known: Boolean;
  NetError: TNetError = neNone;
  LastError: DWORD = 0;
  RemoteName: array[0..MAX_PATH] of WideChar;
  RemoteLength: DWORD;
  I: Integer;
begin
  Result:= False;
  // Mapped network drive: get the server name
  if (Host = '') and (Length(Root) = 2) then
  begin
    RemoteLength:= Length(RemoteName);
    if WNetGetConnectionW(PWideChar(Root), RemoteName, RemoteLength) = NO_ERROR then
    begin
      Host:= RemoteName;
      if (Pos('\\', Host) = 1) then
      begin
        Delete(Host, 1, 2);
        I:= Pos('\', Host);
        if I > 0 then SetLength(Host, I - 1);
      end
      else
        Host:= '';
    end;
  end;

  if (Host <> '') and CanCheckPort(Host, Root) and
     (not HostReachable(Host, Known)) and Known then
  begin
    NetError:= neHost;
    LastError:= ERROR_HOST_UNREACHABLE;
  end
  else if NetCancelled then
    Exit(False)
  else begin
    Attr:= GetFileAttributesW(PWideChar(UTF16LongName(Path)));
    if Attr <> INVALID_FILE_ATTRIBUTES then
      Result:= True
    else begin
      LastError:= GetLastError;
      NetError:= GetNetError(LastError);
    end;
  end;

  // Cancelled: the result is not valid, do not remember it
  if NetCancelled then
    Exit(False);

  FLock.Acquire;
  try
    if not FShutdown then
    begin
      StoreResult(Key, Root, Host, Result, NetError, Background);
      if Result then
        FErrors.Remove(Key)
      else
        FErrors.AddOrSetValue(Key, mbSysErrorMessage(LastError));
    end;
  finally
    FLock.Release;
  end;
end;

{en
   The share was found unreachable recently and is not accessed again,
   keep the previous error message of the path or use a general one.
}
procedure SetDeadRootError(const Path: String);
var
  Key: UnicodeString;
begin
  Key:= MakeKey(CeUtf8ToUtf16(Path));
  FLock.Acquire;
  try
    if (not FShutdown) and (not FErrors.ContainsKey(Key)) then
      FErrors.Add(Key, mbSysErrorMessage(ERROR_BAD_NETPATH));
  finally
    FLock.Release;
  end;
end;

{ TProbeThread }

procedure TProbeThread.Execute;
var
  Notice: TProbeNotice;
begin
  ProbePath(FPath, FKey, FRoot, FHost, True);

  FLock.Acquire;
  try
    if not FShutdown then
    begin
      Notice:= TProbeNotice.Create;
      Notice.Key:= FKey;
      Application.QueueAsyncCall(@Notice.PathChecked, 0);
    end;
  finally
    FLock.Release;
  end;
end;

constructor TProbeThread.Create(const APath: String; const AKey, ARoot,
  AHost: UnicodeString);
begin
  inherited Create(True);
  FreeOnTerminate:= True;
  FPath:= APath;
  FKey:= AKey;
  FRoot:= ARoot;
  FHost:= AHost;
end;

{ TProbeNotice }

procedure TProbeNotice.PathChecked(Data: PtrInt);
begin
  try
    if Assigned(frmMain) and not (csDestroying in frmMain.ComponentState) then
      frmMain.ForEachView(@UpdateView, nil);
  finally
    Free;
  end;
end;

procedure TProbeNotice.UpdateView(AFileView: TFileView; UserData: Pointer);
begin
  if MakeKey(CeUtf8ToUtf16(AFileView.CurrentPath)) = Key then
    AFileView.UpdatePathAvailability;
end;

function IsNetworkPath(const Path: String): Boolean;
var
  Root, Host: UnicodeString;
begin
  Result:= GetNetworkRoot(Path, Root, Host);
end;

function NetPathReachable(const Path: String): Boolean;
var
  Root, Host: UnicodeString;
begin
  if not GetNetworkRoot(Path, Root, Host) then
    Exit(True);

  if RootIsDead(Root, Host, NAVIGATE_NEGATIVE_TTL) then
  begin
    SetDeadRootError(Path);
    Exit(False);
  end;

  Result:= ProbePath(Path, MakeKey(CeUtf8ToUtf16(Path)), Root, Host, False);
end;

function NetHostReachable(const Path: String): Boolean;
var
  Known: Boolean;
  Root, Host: UnicodeString;
begin
  if not GetNetworkRoot(Path, Root, Host) then
    Exit(True);

  if RootIsDead(Root, Host, NAVIGATE_NEGATIVE_TTL) then
  begin
    SetDeadRootError(Path);
    Exit(False);
  end;

  Result:= (Host = '') or (not CanCheckPort(Host, Root)) or
           HostReachable(Host, Known) or (not Known);
  if NetCancelled then
    Exit(False);
  if not Result then
  begin
    FLock.Acquire;
    try
      if not FShutdown then
      begin
        StoreResult(MakeKey(CeUtf8ToUtf16(Path)), Root, Host, False, neHost, False);
        FErrors.AddOrSetValue(MakeKey(CeUtf8ToUtf16(Path)), mbSysErrorMessage(ERROR_HOST_UNREACHABLE));
      end;
    finally
      FLock.Release;
    end;
  end;
end;

function NetPathError(const Path: String): String;
begin
  FLock.Acquire;
  try
    if not FErrors.TryGetValue(MakeKey(CeUtf8ToUtf16(Path)), Result) then
      Result:= EmptyStr;
  finally
    FLock.Release;
  end;
end;

procedure NetSetPathError(const Path, Message: String);
begin
  FLock.Acquire;
  try
    if FShutdown then
      Exit
    else if Length(Message) = 0 then
      FErrors.Remove(MakeKey(CeUtf8ToUtf16(Path)))
    else
      FErrors.AddOrSetValue(MakeKey(CeUtf8ToUtf16(Path)), Message);
  finally
    FLock.Release;
  end;
end;

function NetFileSystemEntryExists(const Path: String; Default: Boolean): Boolean;
var
  Key, Root, Host: UnicodeString;
  Entry: TProbeEntry;
  StartCheck: Boolean = False;
begin
  if not GetNetworkRoot(Path, Root, Host) then
    Exit(mbFileSystemEntryExists(Path));

  Key:= MakeKey(CeUtf8ToUtf16(Path));
  FLock.Acquire;
  try
    if FCache.TryGetValue(Key, Entry) and (Entry.Tick > 0) and
       (GetTickCount64 - Entry.Tick < IfThen(Entry.Exists, POSITIVE_TTL, NEGATIVE_TTL)) then
      Exit(Entry.Exists);
  finally
    FLock.Release;
  end;

  // The share is unreachable, do not access it again for a while
  if RootIsDead(Root, Host, NEGATIVE_TTL) then
    Exit(False);

  FLock.Acquire;
  try
    if FCache.TryGetValue(Key, Entry) and Entry.Pending then
      Exit(Entry.Exists);
    if Entry.Tick = 0 then Entry.Exists:= Default;
    Entry.Pending:= True;
    FCache.AddOrSetValue(Key, Entry);
    Result:= Entry.Exists;
    StartCheck:= True;
  finally
    FLock.Release;
  end;

  if StartCheck then
    TProbeThread.Create(Path, Key, Root, Host).Start;
end;

function NetPathAvailableNow(const Path: String): Boolean;
var
  Root, Host: UnicodeString;
  Entry: TProbeEntry;
begin
  if not GetNetworkRoot(Path, Root, Host) then
    Exit(True);

  FLock.Acquire;
  try
    Result:= FCache.TryGetValue(MakeKey(CeUtf8ToUtf16(Path)), Entry) and
             Entry.Exists and (Entry.Tick > 0) and
             (GetTickCount64 - Entry.Tick < POSITIVE_TTL);
  finally
    FLock.Release;
  end;

  if not Result then
    NetFileSystemEntryExists(Path, True);
end;

procedure NetPathResetCache(const Path: String);
var
  Root, Host: UnicodeString;
begin
  if GetNetworkRoot(Path, Root, Host) then
  begin
    FLock.Acquire;
    try
      FDeadRoots.Remove(Root);
      if Host <> '' then FDeadRoots.Remove(HostKey(Host));
      FCache.Clear;
      FErrors.Clear;
    finally
      FLock.Release;
    end;
  end;
end;

procedure NetCancelThread(Thread: TThread);
begin
  if not Assigned(Thread) then Exit;
  FLock.Acquire;
  try
    if FShutdown then Exit;
    FCancelled.AddOrSetValue(Thread.ThreadID, ThreadCreationTime(Thread.Handle));
  finally
    FLock.Release;
  end;
  CancelSynchronousIo(Thread.Handle);
end;

procedure NetCancelReset;
begin
  FLock.Acquire;
  try
    if Assigned(FCancelled) then
      FCancelled.Remove(GetCurrentThreadId);
  finally
    FLock.Release;
  end;
end;

initialization
  FLock:= SyncObjs.TCriticalSection.Create;
  FCache:= TProbeCache.Create;
  FDeadRoots:= TRootCache.Create;
  FErrors:= TErrorCache.Create;
  FCancelled:= TCancelSet.Create;

finalization
  // Background threads may still be running, they check FShutdown
  // under the lock, so the lock itself is never freed
  FLock.Acquire;
  try
    FShutdown:= True;
    FreeAndNil(FCache);
    FreeAndNil(FDeadRoots);
    FreeAndNil(FErrors);
    FreeAndNil(FCancelled);
  finally
    FLock.Release;
  end;

end.
