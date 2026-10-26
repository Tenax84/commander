{
   Double Commander
   -------------------------------------------------------------------------
   Checks the availability of network paths without freezing the user
   interface (macOS version, see platform/win/unetpathprobe.pas).

   Accessing a directory on an unreachable network volume (SMB, AFP, NFS,
   WebDAV mounted under /Volumes) blocks the calling thread until the
   timeout of the file system expires. Therefore network paths are not
   accessed from the main thread:
   - the panel changes to a network path at once, the file list is loaded
     in the background and an unreachable path is reported in the panel;
   - before accessing the volume a quick TCP connect to the server is
     tried, an unreachable server is detected in about two seconds;
   - unreachable volumes are remembered for a while, so repeated checks
     (e.g. on panel activation) return immediately.

   The network volumes are found in the mount table (getfsstat with
   MNT_NOWAIT does not access the file systems).

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.
}

unit uNetPathProbe;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  Classes;

{en
   Returns @true if Path is on a mounted network volume.
   Does not access the network.
}
function IsNetworkPath(const Path: String): Boolean;
{en
   Checks whether a network path is reachable. Blocks the caller,
   use it from a background thread only. Returns @true for local paths.
}
function NetPathReachable(const Path: String): Boolean;
{en
   Checks only whether the server of a network path is reachable.
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
   Forgets the cached state of the network volume containing Path.
}
procedure NetPathResetCache(const Path: String);
{en
   Cancels the network checks running in Thread. The checks in Thread
   fail until it calls NetCancelReset. A blocking file system call can
   not be interrupted, the file view uses a new thread in that case.
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
  SysUtils, SyncObjs, Math, BaseUnix, UnixType, Sockets, Generics.Collections,
  Forms, DCOSUtils, DCConvertEncoding, uMyUnix, uDarwinIO, uFileView, fMain;

const
  // Positive results are trusted for this time
  POSITIVE_TTL = 10000;
  // Unreachable volumes are remembered for this time
  NEGATIVE_TTL = 30000;
  // Loading a file list retries an unreachable volume sooner
  NAVIGATE_NEGATIVE_TTL = 10000;
  // Timeout of the quick port check
  CONNECT_TIMEOUT = 2000;
  // The port check looks for cancellation this often
  CANCEL_CHECK_INTERVAL = 100;
  // The mount table is read again after this time
  MOUNTS_TTL = 1000;
  MAX_FS = 128;
  // FD_SETSIZE of select
  MAX_FD = 1024;

type
  // Unreachable: nothing, the volume or the whole server
  TNetError = (neNone, neShare, neHost);

  TProbeEntry = record
    Exists: Boolean;
    Tick: QWord;      // when Exists was determined, 0 = never
    Pending: Boolean; // a background check is running
  end;

  TNetMount = record
    MountPoint: String; // with trailing path delimiter
    Host: String;
    Port1, Port2: Word; // 0 = no port check
  end;

  TProbeCache = specialize TDictionary<String, TProbeEntry>;
  TRootCache = specialize TDictionary<String, QWord>;
  TErrorCache = specialize TDictionary<String, String>;
  TCancelSet = specialize TDictionary<TThreadID, Boolean>;
  TMountList = array of TNetMount;

  { TProbeThread }

  TProbeThread = class(TThread)
  private
    FPath: String;
    FKey: String;
    FMount: TNetMount;
  protected
    procedure Execute; override;
  public
    constructor Create(const APath, AKey: String; const AMount: TNetMount); reintroduce;
  end;

  { TProbeNotice }

  TProbeNotice = class
    Key: String;
    procedure PathChecked(Data: PtrInt);
    procedure UpdateView(AFileView: TFileView; UserData: Pointer);
  end;

  PAddrInfo = ^TAddrInfo;
  TAddrInfo = record
    ai_flags: cint;
    ai_family: cint;
    ai_socktype: cint;
    ai_protocol: cint;
    ai_addrlen: TSockLen;
    ai_canonname: PAnsiChar;
    ai_addr: PSockAddr;
    ai_next: PAddrInfo;
  end;

function getaddrinfo(node, service: PAnsiChar; hints: PAddrInfo;
  var res: PAddrInfo): cint; cdecl; external libc name 'getaddrinfo';
procedure freeaddrinfo(res: PAddrInfo); cdecl; external libc name 'freeaddrinfo';

var
  FLock: SyncObjs.TCriticalSection = nil;
  FCache: TProbeCache = nil;
  FDeadRoots: TRootCache = nil;
  FErrors: TErrorCache = nil;
  FCancelled: TCancelSet = nil;
  FMounts: TMountList = nil;
  FMountsTick: QWord = 0;
  FShutdown: Boolean = False;

function NetCancelled: Boolean;
begin
  FLock.Acquire;
  try
    Result:= Assigned(FCancelled) and FCancelled.ContainsKey(GetCurrentThreadId);
  finally
    FLock.Release;
  end;
end;

function MakeKey(const Path: String): String;
begin
  Result:= Path;
  while (Length(Result) > 1) and (Result[Length(Result)] = PathDelim) do
    SetLength(Result, Length(Result) - 1);
end;

{en
   Server name of the mount source:
   smbfs, afpfs: //[domain;][user[:password]@]host[:port]/share
   webdav: http[s]://host[:port]/path
   nfs: host:/path
}
function ParseMountSource(const FSType, Source: String; out Mount: TNetMount): Boolean;
var
  S: String;
  I: Integer;
begin
  Mount.Host:= EmptyStr;
  Mount.Port1:= 0;
  Mount.Port2:= 0;
  S:= Source;
  if FSType = 'smbfs' then
  begin
    Mount.Port1:= 445;
    Mount.Port2:= 139;
  end
  else if FSType = 'afpfs' then
    Mount.Port1:= 548
  else if FSType = 'nfs' then
    Mount.Port1:= 2049
  else if FSType = 'webdav' then
  begin
    if Pos('https:', LowerCase(S)) = 1 then Mount.Port1:= 443 else Mount.Port1:= 80;
  end
  else
    Exit(False);
  Result:= True;

  if FSType = 'nfs' then
  begin
    I:= Pos(':', S);
    if I > 0 then Mount.Host:= Copy(S, 1, I - 1);
  end
  else begin
    I:= Pos('//', S);
    if I = 0 then Exit;
    Delete(S, 1, I + 1);
    I:= Pos('/', S);
    if I > 0 then SetLength(S, I - 1);
    I:= LastDelimiter('@', S);
    if I > 0 then Delete(S, 1, I);
    // Explicit port
    I:= Pos(':', S);
    if (I > 0) and (Pos(':', Copy(S, I + 1, MaxInt)) = 0) then
    begin
      Mount.Port1:= StrToIntDef(Copy(S, I + 1, MaxInt), Mount.Port1);
      Mount.Port2:= 0;
      SetLength(S, I - 1);
    end;
    // Bonjour service name (host._smb._tcp.local), usually the host name
    I:= Pos('._', S);
    if I > 0 then S:= Copy(S, 1, I - 1) + '.local';
    // Percent-encoded names are not resolved, the port check is skipped
    if Pos('%', S) > 0 then S:= EmptyStr;
    Mount.Host:= S;
  end;
end;

{en
   Reads the network volumes from the mount table, without
   accessing the file systems. The caller holds the lock.
}
procedure UpdateMounts;
var
  I, Count: Integer;
  Mount: TNetMount;
  fsList: array[0..MAX_FS - 1] of TDarwinStatfs;
begin
  if (FMountsTick > 0) and (GetTickCount64 - FMountsTick < MOUNTS_TTL) then Exit;
  FMountsTick:= GetTickCount64;
  SetLength(FMounts, 0);
  Count:= getfsstat(@fsList[0], SizeOf(fsList), MNT_NOWAIT);
  for I:= 0 to Count - 1 do
  begin
    if not ParseMountSource(StrPas(fsList[I].fstypename),
                            StrPas(fsList[I].mntfromname), Mount) then
      Continue;
    Mount.MountPoint:= IncludeTrailingPathDelimiter(CeSysToUtf8(StrPas(fsList[I].mountpoint)));
    if Mount.MountPoint = PathDelim then Continue;
    SetLength(FMounts, Length(FMounts) + 1);
    FMounts[High(FMounts)]:= Mount;
  end;
end;

{en
   Returns @true if Path is on a network volume, Mount is the volume.
}
function GetNetworkMount(const Path: String; out Mount: TNetMount): Boolean;
var
  I: Integer;
  S: String;
begin
  Result:= False;
  if (Length(Path) = 0) or (Path[1] <> PathDelim) then Exit;
  S:= IncludeTrailingPathDelimiter(Path);
  FLock.Acquire;
  try
    if FShutdown then Exit;
    UpdateMounts;
    for I:= 0 to High(FMounts) do
    begin
      if (Pos(FMounts[I].MountPoint, S) = 1) and
         ((not Result) or (Length(FMounts[I].MountPoint) > Length(Mount.MountPoint))) then
      begin
        Mount:= FMounts[I];
        Result:= True;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function RootKey(const Mount: TNetMount): String;
begin
  Result:= MakeKey(Mount.MountPoint);
end;

function HostKey(const Mount: TNetMount): String;
begin
  Result:= '//' + LowerCase(Mount.Host);
end;

function IsLoopback(Addr: PAddrInfo): Boolean;
const
  Loopback6: array[0..15] of Byte = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
begin
  case Addr^.ai_family of
    // sockaddr_in: length, family, port, address
    AF_INET: Result:= (PByte(Addr^.ai_addr)[4] = 127);
    // sockaddr_in6: length, family, port, flow info, address
    AF_INET6: Result:= CompareMem(PByte(Addr^.ai_addr) + 8, @Loopback6[0], 16);
    else Result:= False;
  end;
end;

{en
   Tries to connect to the ports of the server. Known is @false if the
   result can not be determined (the name can not be resolved, etc).
}
function HostReachable(const Mount: TNetMount; out Known: Boolean): Boolean;
const
  MAX_SOCKETS = 8;
var
  I, Count, MaxFd: Integer;
  Port: Word;
  Ports: array[0..1] of Word;
  Hints: TAddrInfo;
  AddrList, Addr: PAddrInfo;
  Sockets: array[0..MAX_SOCKETS - 1] of cint;
  Alive: array[0..MAX_SOCKETS - 1] of Boolean;
  Buffer: array[0..127] of Byte;
  WriteSet: TFDSet;
  TimeVal: TTimeVal;
  StartTime, Elapsed: QWord;
  SockError: cint;
  OptLen: TSockLen;
begin
  Result:= False;
  Known:= False;
  if (Mount.Host = EmptyStr) or (Mount.Port1 = 0) then Exit;
  Ports[0]:= Mount.Port1;
  Ports[1]:= Mount.Port2;
  FillChar(Hints, SizeOf(Hints), 0);
  Hints.ai_family:= AF_UNSPEC;
  Hints.ai_socktype:= SOCK_STREAM;
  Hints.ai_protocol:= IPPROTO_TCP;
  AddrList:= nil;
  if getaddrinfo(PAnsiChar(Mount.Host), nil, @Hints, AddrList) <> 0 then Exit;
  try
    // Loopback address: the volume may be served by a local process
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
      if (Addr^.ai_addrlen > SizeOf(Buffer)) or
         ((Addr^.ai_family <> AF_INET) and (Addr^.ai_family <> AF_INET6)) then
      begin
        Addr:= Addr^.ai_next;
        Continue;
      end;
      for Port in Ports do
      begin
        if (Port = 0) or (Count >= MAX_SOCKETS) then Continue;
        Sockets[Count]:= fpSocket(Addr^.ai_family, SOCK_STREAM, IPPROTO_TCP);
        if Sockets[Count] < 0 then Continue;
        if Sockets[Count] >= MAX_FD then
        begin
          CloseSocket(Sockets[Count]);
          Continue;
        end;
        FpFcntl(Sockets[Count], F_SetFl, FpFcntl(Sockets[Count], F_GetFl) or O_NONBLOCK);
        Move(Addr^.ai_addr^, Buffer, Addr^.ai_addrlen);
        // sin_port and sin6_port have the same offset
        PWord(@Buffer[2])^:= htons(Port);
        if fpConnect(Sockets[Count], PSockAddr(@Buffer), Addr^.ai_addrlen) = 0 then
          Result:= True
        else if SocketError <> ESysEINPROGRESS then
        begin
          CloseSocket(Sockets[Count]);
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
      fpFD_ZERO(WriteSet);
      MaxFd:= -1;
      for I:= 0 to Count - 1 do
        if Alive[I] then
        begin
          fpFD_SET(Sockets[I], WriteSet);
          MaxFd:= Max(MaxFd, Sockets[I]);
        end;
      if MaxFd < 0 then Break;
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
      I:= fpSelect(MaxFd + 1, nil, @WriteSet, nil, @TimeVal);
      if I < 0 then
      begin
        if fpGetErrno = ESysEINTR then Continue;
        Break;
      end;
      if I = 0 then Continue;
      for I:= 0 to Count - 1 do
      begin
        if not (Alive[I] and (fpFD_ISSET(Sockets[I], WriteSet) <> 0)) then Continue;
        // The socket is writable when the connection succeeded or failed
        SockError:= 0;
        OptLen:= SizeOf(SockError);
        if (fpGetSockOpt(Sockets[I], SOL_SOCKET, SO_ERROR, @SockError, @OptLen) = 0) and
           (SockError = 0) then
          Result:= True
        else
          Alive[I]:= False;
      end;
    end;

    for I:= 0 to Count - 1 do
      CloseSocket(Sockets[I]);
  finally
    freeaddrinfo(AddrList);
  end;
end;

{en
   Returns @true if the volume or the whole server was found unreachable
   within TimeToLive.
}
function RootIsDead(const Mount: TNetMount; TimeToLive: QWord): Boolean;
var
  Tick: QWord;
begin
  FLock.Acquire;
  try
    if FShutdown then Exit(False);
    Result:= FDeadRoots.TryGetValue(RootKey(Mount), Tick) and (GetTickCount64 - Tick < TimeToLive);
    if (not Result) and (Mount.Host <> '') then
      Result:= FDeadRoots.TryGetValue(HostKey(Mount), Tick) and (GetTickCount64 - Tick < TimeToLive);
  finally
    FLock.Release;
  end;
end;

{en
   Stores the result of a check. The caller holds the lock.
}
procedure StoreResult(const Key: String; const Mount: TNetMount; Exists: Boolean;
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
        FDeadRoots.Remove(RootKey(Mount));
        if Mount.Host <> '' then FDeadRoots.Remove(HostKey(Mount));
      end;
    neShare:
      FDeadRoots.AddOrSetValue(RootKey(Mount), GetTickCount64);
    neHost:
      begin
        FDeadRoots.AddOrSetValue(RootKey(Mount), GetTickCount64);
        if Mount.Host <> '' then FDeadRoots.AddOrSetValue(HostKey(Mount), GetTickCount64);
      end;
  end;
end;

function GetNetError(Error: cint): TNetError;
begin
  case Error of
    ESysEHOSTUNREACH,
    ESysEHOSTDOWN,
    ESysENETUNREACH,
    ESysENETDOWN,
    ESysECONNREFUSED,
    ESysETIMEDOUT:
      Result:= neHost;
    ESysEIO,
    ESysENXIO,
    ESysENOTCONN,
    ESysECONNRESET,
    ESysESTALE:
      Result:= neShare;
    else
      Result:= neNone;
  end;
end;

{en
   Checks the path and stores the result in the cache.
   Blocks the caller until the check finishes.
}
function ProbePath(const Path, Key: String; const Mount: TNetMount;
                   Background: Boolean): Boolean;
var
  Known: Boolean;
  NetError: TNetError = neNone;
  LastError: cint = 0;
  StatInfo: TStat;
begin
  Result:= False;
  if (not HostReachable(Mount, Known)) and Known then
  begin
    NetError:= neHost;
    LastError:= ESysEHOSTUNREACH;
  end
  else if NetCancelled then
    Exit(False)
  else begin
    if fpStat(CeUtf8ToSys(Path), StatInfo) = 0 then
      Result:= True
    else begin
      LastError:= fpGetErrno;
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
      StoreResult(Key, Mount, Result, NetError, Background);
      if Result then
        FErrors.Remove(Key)
      else
        FErrors.AddOrSetValue(Key, SysErrorMessage(LastError));
    end;
  finally
    FLock.Release;
  end;
end;

{en
   The volume was found unreachable recently and is not accessed again,
   keep the previous error message of the path or use a general one.
}
procedure SetDeadRootError(const Path: String);
var
  Key: String;
begin
  Key:= MakeKey(Path);
  FLock.Acquire;
  try
    if (not FShutdown) and (not FErrors.ContainsKey(Key)) then
      FErrors.Add(Key, SysErrorMessage(ESysEHOSTUNREACH));
  finally
    FLock.Release;
  end;
end;

{ TProbeThread }

procedure TProbeThread.Execute;
var
  Notice: TProbeNotice;
begin
  // Thread IDs are reused, a new thread is never cancelled
  NetCancelReset;
  ProbePath(FPath, FKey, FMount, True);

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

constructor TProbeThread.Create(const APath, AKey: String; const AMount: TNetMount);
begin
  inherited Create(True);
  FreeOnTerminate:= True;
  FPath:= APath;
  FKey:= AKey;
  FMount:= AMount;
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
  if MakeKey(AFileView.CurrentPath) = Key then
    AFileView.UpdatePathAvailability;
end;

function IsNetworkPath(const Path: String): Boolean;
var
  Mount: TNetMount;
begin
  Result:= GetNetworkMount(Path, Mount);
end;

function NetPathReachable(const Path: String): Boolean;
var
  Mount: TNetMount;
begin
  if not GetNetworkMount(Path, Mount) then
    Exit(True);

  if RootIsDead(Mount, NAVIGATE_NEGATIVE_TTL) then
  begin
    SetDeadRootError(Path);
    Exit(False);
  end;

  Result:= ProbePath(Path, MakeKey(Path), Mount, False);
end;

function NetHostReachable(const Path: String): Boolean;
var
  Known: Boolean;
  Mount: TNetMount;
begin
  if not GetNetworkMount(Path, Mount) then
    Exit(True);

  if RootIsDead(Mount, NAVIGATE_NEGATIVE_TTL) then
  begin
    SetDeadRootError(Path);
    Exit(False);
  end;

  Result:= HostReachable(Mount, Known) or (not Known);
  if NetCancelled then
    Exit(False);
  if not Result then
  begin
    FLock.Acquire;
    try
      if not FShutdown then
      begin
        StoreResult(MakeKey(Path), Mount, False, neHost, False);
        FErrors.AddOrSetValue(MakeKey(Path), SysErrorMessage(ESysEHOSTUNREACH));
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
    if FShutdown or not FErrors.TryGetValue(MakeKey(Path), Result) then
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
      FErrors.Remove(MakeKey(Path))
    else
      FErrors.AddOrSetValue(MakeKey(Path), Message);
  finally
    FLock.Release;
  end;
end;

function NetFileSystemEntryExists(const Path: String; Default: Boolean): Boolean;
var
  Key: String;
  Mount: TNetMount;
  Entry: TProbeEntry;
  StartCheck: Boolean = False;
begin
  if not GetNetworkMount(Path, Mount) then
    Exit(mbFileSystemEntryExists(Path));

  Key:= MakeKey(Path);
  FLock.Acquire;
  try
    if FShutdown then Exit(Default);
    if FCache.TryGetValue(Key, Entry) and (Entry.Tick > 0) and
       (GetTickCount64 - Entry.Tick < IfThen(Entry.Exists, POSITIVE_TTL, NEGATIVE_TTL)) then
      Exit(Entry.Exists);
  finally
    FLock.Release;
  end;

  // The volume is unreachable, do not access it again for a while
  if RootIsDead(Mount, NEGATIVE_TTL) then
    Exit(False);

  FLock.Acquire;
  try
    if FShutdown then Exit(Default);
    if not FCache.TryGetValue(Key, Entry) then
    begin
      Entry.Tick:= 0;
      Entry.Pending:= False;
    end;
    if Entry.Pending then
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
    TProbeThread.Create(Path, Key, Mount).Start;
end;

function NetPathAvailableNow(const Path: String): Boolean;
var
  Mount: TNetMount;
  Entry: TProbeEntry;
begin
  if not GetNetworkMount(Path, Mount) then
    Exit(True);

  FLock.Acquire;
  try
    Result:= (not FShutdown) and FCache.TryGetValue(MakeKey(Path), Entry) and
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
  Mount: TNetMount;
begin
  if GetNetworkMount(Path, Mount) then
  begin
    FLock.Acquire;
    try
      if FShutdown then Exit;
      FDeadRoots.Remove(RootKey(Mount));
      if Mount.Host <> '' then FDeadRoots.Remove(HostKey(Mount));
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
    FCancelled.AddOrSetValue(Thread.ThreadID, True);
  finally
    FLock.Release;
  end;
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
    FMounts:= nil;
  finally
    FLock.Release;
  end;

end.
