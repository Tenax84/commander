{
   Double Commander
   -------------------------------------------------------------------------
   Self-update from GitHub releases (macOS version, see
   platform/win/uselfupdate.pas).

   On startup a background thread asks the GitHub API for the latest
   release of the repository. If it is newer than the running version,
   the user is asked whether to install it. The disk image of the CPU
   architecture is downloaded, the application bundle is copied from it,
   and after the program has exited a shell script replaces the bundle
   (and starts the new version if requested). If the bundle can not be
   replaced (it is not writable, or it runs translocated or from the disk
   image), the downloaded disk image is opened for a manual installation.

   The version is read from the Info.plist of the bundle, it is set from
   CommanderVersion of platform/win/uselfupdate.pas by
   devtools/macos/build-mac.sh. Only the bundles built by that script
   (bundle identifier com.tenax84.commander) are updated.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.
}

unit uSelfUpdate;

{$mode objfpc}{$H+}
{$modeswitch objectivec2}

interface

const
  CommanderRepository = 'Tenax84/commander';

{en
   Version of this fork (empty if the program does not run from
   a Commander application bundle).
}
function CommanderVersion: String;
{en
   Starts checking for a new release in a background thread.
}
procedure StartUpdateCheck;

implementation

uses
  Classes, SysUtils, BaseUnix, Process, fpjson, jsonparser, CocoaAll,
  uGlobsPaths, uShowMsg, uLng, uDebug, fMain;

const
  ApiUrl = 'https://api.github.com/repos/' + CommanderRepository + '/releases/latest';
  BundleIdentifier = 'com.tenax84.commander';
  // The version the user does not want to be offered again
  SkipFileName = 'update-skip.txt';
{$IF DEFINED(CPUAARCH64)}
  AssetSuffix = '-macos-arm64.dmg';
{$ELSE}
  AssetSuffix = '-macos-x86_64.dmg';
{$ENDIF}

  // Runs after the program has exited: $1 process ID, $2 bundle,
  // $3 new bundle, $4 restart (1/0), $5 temporary directory,
  // $6 settings directory inside the bundle (relative, may be empty)
  InstallScript =
    'while kill -0 "$1" 2>/dev/null; do sleep 0.5; done' + LineEnding +
    'if [ -n "$6" ] && [ -d "$2/$6" ]; then rm -rf "$3/$6"; /usr/bin/ditto "$2/$6" "$3/$6"; fi' + LineEnding +
    'rm -rf "$2.updold"' + LineEnding +
    'if mv "$2" "$2.updold"; then' + LineEnding +
    '  if mv "$3" "$2"; then rm -rf "$2.updold"; else mv "$2.updold" "$2"; fi' + LineEnding +
    'fi' + LineEnding +
    '/usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null' + LineEnding +
    'if [ "$4" = 1 ]; then /usr/bin/open "$2"; fi' + LineEnding +
    'rm -rf "$5"';

type

  { TUpdateThread }

  TUpdateThread = class(TThread)
  private
    FVersion: String;
    FAssetUrl: String;
    FTempDir: String;
    FNewBundle: String;
    function CheckRelease: Boolean;
    procedure Restart;
    procedure RunAfterExit(ARestart: Boolean);
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

var
  FBundlePath: String = '';
  FVersionRead: Boolean = False;
  FCommanderVersion: String = '';

function BundleString(const Key: String): String;
var
  Value: id;
begin
  Result:= EmptyStr;
  Value:= NSBundle.mainBundle.objectForInfoDictionaryKey(NSSTR(Key));
  if Assigned(Value) and Value.isKindOfClass(NSString) then
    Result:= NSString(Value).UTF8String;
end;

function CommanderVersion: String;
begin
  if not FVersionRead then
  begin
    FVersionRead:= True;
    FBundlePath:= NSBundle.mainBundle.bundlePath.UTF8String;
    if (LowerCase(ExtractFileExt(FBundlePath)) = '.app') and
       (BundleString('CFBundleIdentifier') = BundleIdentifier) then
      FCommanderVersion:= BundleString('CFBundleShortVersionString');
  end;
  Result:= FCommanderVersion;
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

{en
   Runs a command line tool, raises an exception if it fails.
}
function RunTool(const AExe: String; const AArgs: array of String): String;
var
  ExitStatus: Integer;
begin
  if RunCommandIndir(EmptyStr, AExe, AArgs, Result, ExitStatus) <> 0 then
    raise Exception.Create(AExe + ': can not be started');
  if ExitStatus <> 0 then
    raise Exception.CreateFmt('%s: exit code %d', [ExtractFileName(AExe), ExitStatus]);
end;

{en
   Downloads an URL by curl (it uses the system certificates and proxy).
}
function HttpGet(const AUrl: String; const AFileName: String = ''): String;
begin
  if AFileName = EmptyStr then
    Result:= RunTool('/usr/bin/curl', ['-fsL', '--connect-timeout', '15', '-m', '60',
                     '-A', 'Commander/' + CommanderVersion,
                     '-H', 'Accept: application/vnd.github+json', AUrl])
  else
    Result:= RunTool('/usr/bin/curl', ['-fsL', '--connect-timeout', '15',
                     '-A', 'Commander/' + CommanderVersion, '-o', AFileName, AUrl]);
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

procedure DeleteDirectory(const ADir: String);
begin
  if DirectoryExists(ADir) then
  try
    RunTool('/bin/rm', ['-rf', ExcludeTrailingPathDelimiter(ADir)]);
  except
    on E: Exception do DCDebug('Update: ' + E.Message);
  end;
end;

{en
   Returns @true if the application bundle can be replaced: it is writable
   and does not run translocated (from a quarantined download) or from
   the disk image.
}
function CanReplaceBundle: Boolean;
begin
  Result:= (FBundlePath <> EmptyStr) and
           (Pos('/AppTranslocation/', FBundlePath) = 0) and
           (fpAccess(FBundlePath, W_OK) = 0) and
           (fpAccess(ExtractFileDir(FBundlePath), W_OK) = 0);
end;

procedure StartUpdateCheck;
begin
  if CommanderVersion <> EmptyStr then
    TUpdateThread.Create;
end;

{ TUpdateThread }

constructor TUpdateThread.Create;
begin
  FreeOnTerminate:= True;
  inherited Create(False);
end;

function TUpdateThread.CheckRelease: Boolean;
var
  I: Integer;
  Name: String;
  Json: TJSONData;
  Assets: TJSONArray;
begin
  Result:= False;
  // The environment variable allows testing with a local server
  Name:= GetEnvironmentVariable('COMMANDER_UPDATE_URL');
  if Name = EmptyStr then Name:= ApiUrl;
  Json:= GetJSON(HttpGet(Name));
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
      if (Length(Name) > Length(AssetSuffix)) and
         (Copy(Name, Length(Name) - Length(AssetSuffix) + 1, MaxInt) = AssetSuffix) then
        FAssetUrl:= Assets.Objects[I].Get('browser_download_url', '');
    end;
    Result:= FAssetUrl <> EmptyStr;
  finally
    Json.Free;
  end;
end;

procedure TUpdateThread.Restart;
begin
  RunAfterExit(True);
end;

{en
   Starts a shell script that waits until this process has finished,
   then replaces the application bundle and starts it again if requested.
}
procedure TUpdateThread.RunAfterExit(ARestart: Boolean);
var
  Settings: String = '';
  Script: TProcess;
begin
  // Portable settings inside the bundle are kept
  if Pos(IncludeTrailingPathDelimiter(FBundlePath), gpCfgDir) = 1 then
    Settings:= ExcludeTrailingPathDelimiter(Copy(gpCfgDir, Length(FBundlePath) + 2, MaxInt));
  Script:= TProcess.Create(nil);
  try
    Script.Executable:= '/bin/sh';
    Script.Parameters.Add('-c');
    Script.Parameters.Add(InstallScript);
    Script.Parameters.Add('commander-update');
    Script.Parameters.Add(IntToStr(FpGetpid));
    Script.Parameters.Add(FBundlePath);
    Script.Parameters.Add(FNewBundle);
    Script.Parameters.Add(BoolToStr(ARestart, '1', '0'));
    Script.Parameters.Add(ExcludeTrailingPathDelimiter(FTempDir));
    Script.Parameters.Add(Settings);
    try
      Script.Execute;
      if ARestart then frmMain.Close;
    except
      on E: Exception do
        if GetCurrentThreadId = MainThreadID then
          msgError(Format(rsMsgUpdateFailed, [E.Message]))
        else
          msgError(Self, Format(rsMsgUpdateFailed, [E.Message]));
    end;
  finally
    Script.Free;
  end;
end;

procedure TUpdateThread.Execute;
var
  DmgName, MountDir: String;
  SearchRec: TSearchRec;
  Mounted: Boolean = False;
begin
  try
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

  FTempDir:= IncludeTrailingPathDelimiter(GetTempDir(False)) + 'Commander-update' + PathDelim;
  try
    DeleteDirectory(FTempDir);
    ForceDirectories(FTempDir);
    DmgName:= FTempDir + 'Commander-' + FVersion + AssetSuffix;
    HttpGet(FAssetUrl, DmgName);

    // The bundle can not be replaced, the user installs the new version
    if not CanReplaceBundle then
    begin
      RunTool('/usr/bin/open', [DmgName]);
      msgOK(Self, Format(rsMsgUpdateOpenDiskImage, [FVersion]));
      Exit;
    end;

    MountDir:= FTempDir + 'mnt';
    ForceDirectories(MountDir);
    RunTool('/usr/bin/hdiutil', ['attach', '-nobrowse', '-noautoopen', '-readonly',
                                 '-mountpoint', MountDir, DmgName]);
    Mounted:= True;
    try
      if FindFirst(MountDir + PathDelim + '*.app', faAnyFile, SearchRec) = 0 then
      try
        FNewBundle:= FTempDir + SearchRec.Name;
        RunTool('/usr/bin/ditto', [MountDir + PathDelim + SearchRec.Name, FNewBundle]);
      finally
        FindClose(SearchRec);
      end;
    finally
      if Mounted then
      try
        RunTool('/usr/bin/hdiutil', ['detach', MountDir, '-force']);
      except
        on E: Exception do DCDebug('Update: ' + E.Message);
      end;
    end;
    if (FNewBundle = EmptyStr) or not FileExists(FNewBundle + '/Contents/Info.plist') then
      raise Exception.Create('The application was not found in the downloaded disk image');
  except
    on E: Exception do
    begin
      msgError(Self, Format(rsMsgUpdateFailed, [E.Message]));
      Exit;
    end;
  end;

  // No: the update is installed when the user closes the program
  if MsgBox(Self, Format(rsMsgUpdateDownloaded, [FVersion]), [msmbYes, msmbNo],
            msmbYes, msmbNo) = mmrYes then
    Synchronize(@Restart)
  else
    RunAfterExit(False);
end;

end.
