{
   Double commander
   -------------------------------------------------------------------------
   Wfx plugin for working with File Transfer Protocol

   Import of Total Commander FTP connections (wcx_ftp.ini)

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA
}

unit FtpTcImport;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes;

type

  { TTcConnection }

  TTcConnection = record
    Name: String;
    Host: String;
    Port: String;
    Path: String;
    UserName: String;
    Password: String;
    PasswordLost: Boolean; // Protected by the TC master password
    PassiveMode: Boolean;
    AutoTLS: Boolean;
    FullSSL: Boolean;
    OpenSSH: Boolean;
  end;

  TTcConnections = array of TTcConnection;

{en
   Decodes a password stored in wcx_ftp.ini (hex string, TC obfuscation).
   Returns False if the value cannot be decoded (e.g. master password).
}
function TcDecodePassword(const Value: String; out Password: String): Boolean;
{en
   Returns the location of the Total Commander wcx_ftp.ini file
   or an empty string if it is not found.
}
function TcFindFtpIniFile: String;
{en
   Reads the connection list from a Total Commander wcx_ftp.ini file.
}
function TcReadConnections(const FileName: String): TTcConnections;

implementation

uses
  IniFiles, StrUtils, LazUTF8, DCConvertEncoding, FtpUtils
  {$IFDEF MSWINDOWS}
  , Windows, Registry
  {$ENDIF}
  ;

const
  TcFtpIniName = 'wcx_ftp.ini';

var
  TcSeed: LongWord;

function ToUtf8(const Value: String): String;
begin
  if FindInvalidUTF8Codepoint(PChar(Value), Length(Value)) < 0 then
    Result:= Value
  else
    Result:= CeSysToUtf8(Value);
end;

{$PUSH}{$Q-}{$R-}
// Delphi Random() algorithm used by Total Commander
function TcRandom(Max: LongWord): LongWord;
begin
  TcSeed:= TcSeed * $08088405 + 1;
  Result:= LongWord((QWord(TcSeed) * Max) shr 32);
end;

function TcDecodePassword(const Value: String; out Password: String): Boolean;
var
  T: Byte;
  Data: TBytes;
  I, A, B, R, Count, Len: Integer;
begin
  Password:= EmptyStr;
  Count:= Length(Value) div 2;
  if (Count < 5) or Odd(Length(Value)) then Exit(False);
  SetLength(Data, Count);
  for I:= 0 to Count - 1 do
  begin
    if not TryStrToInt('$' + Copy(Value, I * 2 + 1, 2), R) then Exit(False);
    Data[I]:= Byte(R);
  end;
  Len:= Count - 4;
  TcSeed:= 849521;
  for I:= 0 to Count - 1 do
  begin
    R:= TcRandom(8);
    Data[I]:= Byte((Data[I] shl R) or (Data[I] shr (8 - R)));
  end;
  TcSeed:= 12345;
  for I:= 0 to 255 do
  begin
    A:= TcRandom(Len);
    B:= TcRandom(Len);
    T:= Data[A]; Data[A]:= Data[B]; Data[B]:= T;
  end;
  TcSeed:= 42340;
  for I:= 0 to Len do
    Data[I]:= Data[I] xor TcRandom(256);
  TcSeed:= 54321;
  for I:= 0 to Len do
    Data[I]:= Byte(Data[I] - TcRandom(256));
  SetLength(Password, Len);
  if Len > 0 then Move(Data[0], Password[1], Len);
  Result:= Pos(#0, Password) = 0;
  if Result then
    Password:= ToUtf8(Password)
  else
    Password:= EmptyStr;
end;
{$POP}

function TcFindFtpIniFile: String;
var
  Candidates: TStringList;

  procedure AddCandidate(const Path: String);
  var
    FileName: String;
  begin
    FileName:= Trim(Path);
    if FileName = EmptyStr then Exit;
    FileName:= ExpandFileName(FileName);
    if Candidates.IndexOf(FileName) < 0 then Candidates.Add(FileName);
  end;

  procedure AddDirectory(const Path: String);
  begin
    if Trim(Path) <> EmptyStr then
      AddCandidate(IncludeTrailingPathDelimiter(Trim(Path)) + TcFtpIniName);
  end;

{$IFDEF MSWINDOWS}
  function ExpandEnv(const Value: String): String;
  var
    Len: DWORD;
    Source, Target: UnicodeString;
  begin
    Source:= CeUtf8ToUtf16(Value);
    Len:= ExpandEnvironmentStringsW(PWideChar(Source), nil, 0);
    if Len = 0 then Exit(Value);
    SetLength(Target, Len);
    ExpandEnvironmentStringsW(PWideChar(Source), PWideChar(Target), Len);
    Result:= CeUtf16ToUtf8(PWideChar(Target));
  end;

  procedure AddFromRegistry(RootKey: HKEY);
  var
    Reg: TRegistry;
  begin
    Reg:= TRegistry.Create(KEY_READ);
    try
      Reg.RootKey:= RootKey;
      if Reg.OpenKeyReadOnly('Software\Ghisler\Total Commander') then
      begin
        if Reg.ValueExists('FtpIniName') then
          AddCandidate(ExpandEnv(Reg.ReadString('FtpIniName')));
        if Reg.ValueExists('IniFileName') then
          AddDirectory(ExtractFileDir(ExpandEnv(Reg.ReadString('IniFileName'))));
        if Reg.ValueExists('InstallDir') then
          AddDirectory(ExpandEnv(Reg.ReadString('InstallDir')));
      end;
    finally
      Reg.Free;
    end;
  end;
{$ENDIF}

var
  I: Integer;
begin
  Result:= EmptyStr;
  Candidates:= TStringList.Create;
  try
    {$IFDEF MSWINDOWS}
    AddFromRegistry(HKEY_CURRENT_USER);
    AddFromRegistry(HKEY_LOCAL_MACHINE);
    AddDirectory(GetEnvironmentVariableUTF8('COMMANDER_PATH'));
    AddDirectory(IncludeTrailingPathDelimiter(GetEnvironmentVariableUTF8('APPDATA')) + 'GHISLER');
    AddDirectory('C:\totalcmd');
    AddDirectory(IncludeTrailingPathDelimiter(GetEnvironmentVariableUTF8('ProgramFiles')) + 'totalcmd');
    {$ENDIF}
    for I:= 0 to Candidates.Count - 1 do
    begin
      if FileExists(Candidates[I]) then
        Exit(Candidates[I]);
    end;
  finally
    Candidates.Free;
  end;
end;

function TcReadConnections(const FileName: String): TTcConnections;
var
  I, Index, Count: Integer;
  Value, Prefix: String;
  Keys, Names: TStringList;
  IniFile: TMemIniFile;
  DefaultPassive: Boolean;
  Connection: TTcConnection;
begin
  Result:= nil;
  Keys:= TStringList.Create;
  Names:= TStringList.Create;
  IniFile:= TMemIniFile.Create(FileName);
  try
    // Connections are listed as 1=Name, 2=Name, ... (other keys like "default" are skipped)
    IniFile.ReadSection('connections', Keys);
    for I:= 0 to Keys.Count - 1 do
    begin
      if TryStrToInt(Keys[I], Index) then
      begin
        Value:= Trim(IniFile.ReadString('connections', Keys[I], EmptyStr));
        if (Value <> EmptyStr) and (Names.IndexOf(Value) < 0) then
          Names.AddObject(Value, TObject(PtrInt(Index)));
      end;
    end;
    DefaultPassive:= IniFile.ReadString('default', 'pasvmode', '1') <> '0';

    Count:= 0;
    SetLength(Result, Names.Count);
    for I:= 0 to Names.Count - 1 do
    begin
      if not IniFile.SectionExists(Names[I]) then Continue;

      Connection:= Default(TTcConnection);
      Connection.Name:= ToUtf8(Names[I]);

      Value:= Trim(IniFile.ReadString(Names[I], 'host', EmptyStr));
      if Value = EmptyStr then Continue;

      Index:= Pos('://', Value);
      if Index > 0 then
      begin
        Prefix:= LowerCase(Copy(Value, 1, Index - 1));
        Connection.OpenSSH:= (Prefix = 'sftp') or (Prefix = 'scp');
        Connection.AutoTLS:= (Prefix = 'ftps');
        Delete(Value, 1, Index + 2);
      end;
      // Host may contain a start directory: server/dir
      Index:= Pos('/', Value);
      if Index > 0 then
      begin
        Connection.Path:= Copy(Value, Index, MaxInt);
        Value:= Copy(Value, 1, Index - 1);
      end;
      Connection.Host:= ExtractConnectionHost(Value);
      Connection.Port:= ExtractConnectionPort(Value);
      if Connection.Host = EmptyStr then Continue;

      if Connection.AutoTLS and (Connection.Port = '990') then
      begin
        Connection.AutoTLS:= False;
        Connection.FullSSL:= True;
      end;

      Value:= IniFile.ReadString(Names[I], 'directory', EmptyStr);
      if Value <> EmptyStr then Connection.Path:= ToUtf8(Value);

      if IniFile.ReadString(Names[I], 'anonymous', '0') = '1' then
        Connection.UserName:= 'anonymous'
      else begin
        Connection.UserName:= ToUtf8(IniFile.ReadString(Names[I], 'username', EmptyStr));
        Value:= Trim(IniFile.ReadString(Names[I], 'password', EmptyStr));
        if Value <> EmptyStr then
        begin
          Connection.PasswordLost:= (Value[1] = '!') or
                                    not TcDecodePassword(Value, Connection.Password);
        end;
      end;

      Value:= IniFile.ReadString(Names[I], 'pasvmode', EmptyStr);
      if Value = EmptyStr then
        Connection.PassiveMode:= DefaultPassive
      else
        Connection.PassiveMode:= (Value <> '0');

      Result[Count]:= Connection;
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    IniFile.Free;
    Names.Free;
    Keys.Free;
  end;
end;

end.
