{
   Double Commander
   -------------------------------------------------------------------------
   Self-update from GitHub releases.

   On startup a background thread asks the GitHub API for the latest
   release of the repository. If it is newer than the running version,
   the user is asked whether to install it. The release zip is downloaded
   and extracted into the program directory. Files in use (the running
   executable, loaded libraries) cannot be overwritten, but they can be
   renamed, so they are moved aside and deleted on the next startup.
   The settings directory is never changed.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.
}

unit uSelfUpdate;

{$mode objfpc}{$H+}

interface

const
  // Version of this fork, the release tag is 'v' + CommanderVersion
  CommanderVersion = '1.0.0';
  CommanderRepository = 'Tenax84/commander';

{en
   Starts checking for a new release in a background thread.
}
procedure StartUpdateCheck;

implementation

uses
  Classes, Windows, WinINet, SysUtils, fpjson, jsonparser, Zipper,
  uGlobsPaths, uShowMsg, uLng, uDebug, fMain;

const
  ApiUrl = 'https://api.github.com/repos/' + CommanderRepository + '/releases/latest';
  ExeName = 'Commander.exe';
  OldSuffix = '.updold';
  // List of the files moved aside, deleted on the next startup
  OldListName = 'update-old.txt';
  // The version the user does not want to be offered again
  SkipFileName = 'update-skip.txt';

type

  { TUpdateThread }

  TUpdateThread = class(TThread)
  private
    FVersion: String;
    FAssetUrl: String;
    FOldFiles: TStringList;
    function CheckRelease: Boolean;
    procedure Download(const AFileName: String);
    procedure Install(const ASourceDir: String);
    procedure InstallFile(const ASource, ATarget: String);
    procedure Restart;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

function ProgramDir: String;
begin
  Result:= ExtractFilePath(ParamStr(0));
end;

function WideName(const S: String): UnicodeString; inline;
begin
  Result:= UTF8Decode(S);
end;

function Max(A, B: Integer): Integer; inline;
begin
  if A > B then Result:= A else Result:= B;
end;

{en
   Compares two dotted version numbers, returns <0, 0 or >0.
}
function CompareVersions(const A, B: String): Integer;
var
  I: Integer;
  PartsA, PartsB: TStringArray;
begin
  PartsA:= A.Split(['.']);
  PartsB:= B.Split(['.']);
  for I:= 0 to Max(Length(PartsA), Length(PartsB)) - 1 do
  begin
    Result:= 0;
    if I < Length(PartsA) then Result:= StrToIntDef(PartsA[I], 0);
    if I < Length(PartsB) then Result-= StrToIntDef(PartsB[I], 0);
    if Result <> 0 then Exit;
  end;
  Result:= 0;
end;

procedure HttpGet(const AUrl: String; AStream: TStream);
const
  Headers: UnicodeString = 'Accept: application/vnd.github+json'#13#10;
  Timeout: DWORD = 15000;
var
  hNet, hUrl: HINTERNET;
  Buffer: array[0..65535] of Byte;
  BytesRead, Status, Size, Index: DWORD;
begin
  hNet:= InternetOpenW(PWideChar(WideName('Commander/' + CommanderVersion)),
                       INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then RaiseLastOSError;
  try
    InternetSetOptionW(hNet, INTERNET_OPTION_CONNECT_TIMEOUT, @Timeout, SizeOf(Timeout));
    InternetSetOptionW(hNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @Timeout, SizeOf(Timeout));
    hUrl:= InternetOpenUrlW(hNet, PWideChar(WideName(AUrl)), PWideChar(Headers),
                            Length(Headers), INTERNET_FLAG_RELOAD or
                            INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_NO_UI, 0);
    if hUrl = nil then RaiseLastOSError;
    try
      Status:= 0;
      Size:= SizeOf(Status);
      Index:= 0;
      if HttpQueryInfoW(hUrl, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER,
                        @Status, Size, Index) and (Status <> 200) then
        raise Exception.CreateFmt('HTTP %d: %s', [Status, AUrl]);
      repeat
        if not InternetReadFile(hUrl, @Buffer, SizeOf(Buffer), BytesRead) then
          RaiseLastOSError;
        AStream.WriteBuffer(Buffer, BytesRead);
      until BytesRead = 0;
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
  end;
end;

function ReadFirstLine(const AFileName: String): String;
var
  Lines: TStringList;
begin
  Result:= EmptyStr;
  if not FileExists(AFileName) then Exit;
  Lines:= TStringList.Create;
  try
    Lines.LoadFromFile(AFileName);
    if Lines.Count > 0 then Result:= Trim(Lines[0]);
  finally
    Lines.Free;
  end;
end;

procedure WriteFirstLine(const AFileName, AText: String);
var
  Lines: TStringList;
begin
  Lines:= TStringList.Create;
  try
    Lines.Add(AText);
    Lines.SaveToFile(AFileName);
  finally
    Lines.Free;
  end;
end;

{en
   Deletes the files left over by the previous update.
}
procedure DeleteOldFiles;
var
  I: Integer;
  ListName: String;
  Lines: TStringList;
begin
  ListName:= ProgramDir + OldListName;
  if not FileExists(ListName) then Exit;
  Lines:= TStringList.Create;
  try
    Lines.LoadFromFile(ListName);
    for I:= Lines.Count - 1 downto 0 do
    begin
      if (Lines[I] = EmptyStr) or DeleteFileW(PWideChar(WideName(Lines[I]))) or
         (GetFileAttributesW(PWideChar(WideName(Lines[I]))) = INVALID_FILE_ATTRIBUTES) then
        Lines.Delete(I);
    end;
    if Lines.Count = 0 then
      DeleteFile(ListName)
    else
      Lines.SaveToFile(ListName);
  finally
    Lines.Free;
  end;
end;

procedure DeleteDirectory(const ADir: String);
var
  SearchRec: TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, SearchRec) = 0 then
  try
    repeat
      if (SearchRec.Name = '.') or (SearchRec.Name = '..') then Continue;
      if (SearchRec.Attr and faDirectory) <> 0 then
        DeleteDirectory(ADir + SearchRec.Name + PathDelim)
      else
        DeleteFile(ADir + SearchRec.Name);
    until FindNext(SearchRec) <> 0;
  finally
    FindClose(SearchRec);
  end;
  RemoveDir(ADir);
end;

procedure StartUpdateCheck;
begin
  TUpdateThread.Create;
end;

{ TUpdateThread }

constructor TUpdateThread.Create;
begin
  FOldFiles:= TStringList.Create;
  FreeOnTerminate:= True;
  inherited Create(False);
end;

destructor TUpdateThread.Destroy;
begin
  FOldFiles.Free;
  inherited Destroy;
end;

function TUpdateThread.CheckRelease: Boolean;
var
  I: Integer;
  Name: String;
  Json: TJSONData;
  Assets: TJSONArray;
  Stream: TStringStream;
begin
  Result:= False;
  Stream:= TStringStream.Create(EmptyStr);
  try
    // The environment variable allows testing with a local server
    Name:= GetEnvironmentVariable('COMMANDER_UPDATE_URL');
    if Name = EmptyStr then Name:= ApiUrl;
    HttpGet(Name, Stream);
    Json:= GetJSON(Stream.DataString);
  finally
    Stream.Free;
  end;
  try
    if (Json.FindPath('draft') <> nil) and Json.FindPath('draft').AsBoolean then Exit;
    if (Json.FindPath('prerelease') <> nil) and Json.FindPath('prerelease').AsBoolean then Exit;
    FVersion:= Json.FindPath('tag_name').AsString;
    if (FVersion <> EmptyStr) and (FVersion[1] in ['v', 'V']) then Delete(FVersion, 1, 1);
    if CompareVersions(FVersion, CommanderVersion) <= 0 then Exit;
    if ReadFirstLine(gpCfgDir + SkipFileName) = FVersion then Exit;
    if not (Json.FindPath('assets') is TJSONArray) then Exit;
    Assets:= TJSONArray(Json.FindPath('assets'));
    for I:= 0 to Assets.Count - 1 do
    begin
      Name:= LowerCase(Assets.Objects[I].Get('name', ''));
      if (ExtractFileExt(Name) = '.zip') and ((FAssetUrl = EmptyStr) or (Pos('win64', Name) > 0)) then
        FAssetUrl:= Assets.Objects[I].Get('browser_download_url', '');
    end;
    Result:= FAssetUrl <> EmptyStr;
  finally
    Json.Free;
  end;
end;

procedure TUpdateThread.Download(const AFileName: String);
var
  Stream: TFileStream;
begin
  Stream:= TFileStream.Create(AFileName, fmCreate);
  try
    HttpGet(FAssetUrl, Stream);
  finally
    Stream.Free;
  end;
end;

procedure TUpdateThread.InstallFile(const ASource, ATarget: String);
var
  Moved: String;
begin
  if FileExists(ATarget) then
  begin
    // Keep the user's settings
    if SameText(Copy(ATarget, 1, Length(gpCfgDir)), gpCfgDir) then Exit;
    if not DeleteFileW(PWideChar(WideName(ATarget))) then
    begin
      // The file is in use, move it aside
      Moved:= ATarget + OldSuffix;
      DeleteFileW(PWideChar(WideName(Moved)));
      if not MoveFileExW(PWideChar(WideName(ATarget)), PWideChar(WideName(Moved)),
                         MOVEFILE_REPLACE_EXISTING) then
        RaiseLastOSError;
      FOldFiles.Add(Moved);
    end;
  end;
  ForceDirectories(ExtractFilePath(ATarget));
  if not CopyFileW(PWideChar(WideName(ASource)), PWideChar(WideName(ATarget)), False) then
    raise Exception.Create(ATarget + ': ' + SysErrorMessage(GetLastError));
end;

procedure TUpdateThread.Install(const ASourceDir: String);

  procedure InstallDir(const ARelative: String);
  var
    SearchRec: TSearchRec;
  begin
    if FindFirst(ASourceDir + ARelative + '*', faAnyFile, SearchRec) = 0 then
    try
      repeat
        if (SearchRec.Name = '.') or (SearchRec.Name = '..') then Continue;
        if (SearchRec.Attr and faDirectory) <> 0 then
        begin
          // The portable settings directory is created by the user only
          if (ARelative <> EmptyStr) or not SameText(SearchRec.Name, 'settings') then
            InstallDir(ARelative + SearchRec.Name + PathDelim);
        end
        else
          InstallFile(ASourceDir + ARelative + SearchRec.Name,
                      ProgramDir + ARelative + SearchRec.Name);
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;
  end;

var
  ListName: String;
begin
  ListName:= ProgramDir + OldListName;
  if FileExists(ListName) then FOldFiles.LoadFromFile(ListName);
  try
    InstallDir(EmptyStr);
  finally
    if FOldFiles.Count > 0 then FOldFiles.SaveToFile(ListName);
  end;
end;

procedure TUpdateThread.Restart;
var
  Command: UnicodeString;
  StartupInfo: TStartupInfoW;
  ProcessInfo: TProcessInformation;
begin
  // Start the new version after this process has finished
  Command:= WideName(Format('powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command ' +
                            '"Wait-Process -Id %d -ErrorAction SilentlyContinue; Start-Process -FilePath ''%s''"',
                            [GetCurrentProcessId, StringReplace(ProgramDir + ExeName, '''', '''''', [rfReplaceAll])]));
  UniqueString(Command);
  FillChar(StartupInfo, SizeOf(StartupInfo), 0);
  StartupInfo.cb:= SizeOf(StartupInfo);
  if CreateProcessW(nil, PWideChar(Command), nil, nil, False, CREATE_NO_WINDOW,
                    nil, nil, StartupInfo, ProcessInfo) then
  begin
    CloseHandle(ProcessInfo.hThread);
    CloseHandle(ProcessInfo.hProcess);
    frmMain.Close;
  end;
end;

procedure TUpdateThread.Execute;
var
  TempDir, ZipName, SourceDir: String;
  UnZipper: TUnZipper;
  SearchRec: TSearchRec;
begin
  try
    DeleteOldFiles;
    if not CheckRelease then Exit;
  except
    on E: Exception do
    begin
      DCDebug('Update check failed: ' + E.Message);
      Exit;
    end;
  end;

  case MsgBox(Self, Format(rsMsgUpdateAvailable, [FVersion, CommanderVersion]),
              [msmbYes, msmbNo, msmbSkip], msmbYes, msmbNo) of
    mmrYes: ;
    mmrSkip:
      begin
        try
          WriteFirstLine(gpCfgDir + SkipFileName, FVersion);
        except
          // Ignore, the version will be offered again
        end;
        Exit;
      end;
    else Exit;
  end;

  TempDir:= IncludeTrailingPathDelimiter(GetTempDir(False)) + 'Commander-update' + PathDelim;
  try
    try
      DeleteDirectory(TempDir);
      ForceDirectories(TempDir + 'files');
      ZipName:= TempDir + 'update.zip';
      Download(ZipName);
      UnZipper:= TUnZipper.Create;
      try
        UnZipper.FileName:= ZipName;
        UnZipper.OutputPath:= TempDir + 'files';
        UnZipper.UnZipAllFiles;
      finally
        UnZipper.Free;
      end;
      // The zip may contain a single top level directory
      SourceDir:= TempDir + 'files' + PathDelim;
      if not FileExists(SourceDir + ExeName) then
      begin
        if FindFirst(SourceDir + '*', faDirectory, SearchRec) = 0 then
        try
          repeat
            if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') and
               FileExists(SourceDir + SearchRec.Name + PathDelim + ExeName) then
            begin
              SourceDir:= SourceDir + SearchRec.Name + PathDelim;
              Break;
            end;
          until FindNext(SearchRec) <> 0;
        finally
          FindClose(SearchRec);
        end;
      end;
      if not FileExists(SourceDir + ExeName) then
        raise Exception.Create(ExeName + ' not found in the downloaded package');
      Install(SourceDir);
    finally
      DeleteDirectory(TempDir);
    end;
  except
    on E: Exception do
    begin
      msgError(Self, Format(rsMsgUpdateFailed, [E.Message]));
      Exit;
    end;
  end;

  if MsgBox(Self, Format(rsMsgUpdateInstalled, [FVersion]), [msmbYes, msmbNo],
            msmbYes, msmbNo) = mmrYes then
    Synchronize(@Restart);
end;

end.
