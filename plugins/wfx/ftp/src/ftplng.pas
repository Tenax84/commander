unit FtpLng;

{$mode Delphi}

interface

uses
  Classes, SysUtils;

var
  cAddConnection: String;
  cQuickConnection: String;
  cImportConnections: String;

resourcestring
  rsAddConnection = 'Add connection';
  rsQuickConnection = 'Quick connection';
  // Total Commander style
  rsImportConnections = 'Import from Total Commander';
  rsImportFileName = 'Total Commander FTP settings file (wcx_ftp.ini):';
  rsImportFileNotFound = 'File not found:';
  rsImportResult = 'Imported connections: %d';
  rsImportSkipped = 'Skipped (a connection with the same name already exists): %d';
  rsImportNoPassword = 'Passwords that could not be imported (Total Commander master password): %d';

procedure TranslateResourceStrings;

implementation

uses
  FtpFunc;

function Translate(Name, Value: AnsiString; Hash: LongInt; Arg: Pointer): AnsiString;
var
  ALen: Integer;
begin
  with gStartupInfo do
  begin
    SetLength(Result, MaxSmallint);
    ALen:= TranslateString(Translation, PAnsiChar(Name), PAnsiChar(Value), PAnsiChar(Result), MaxSmallint);
    SetLength(Result, ALen);
  end;
end;

procedure TranslateResourceStrings;
begin
  if Assigned(gStartupInfo.Translation) then
  begin
    SetResourceStrings(@Translate, nil);
  end;
  cAddConnection:= '<' + rsAddConnection + '>';
  cQuickConnection:= '<' + rsQuickConnection + '>';
  cImportConnections:= '<' + rsImportConnections + '>';
end;

end.

