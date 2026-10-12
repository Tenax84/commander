{
   Double Commander
   -------------------------------------------------------------------------
   Total Commander style look of the main window.

   The changes are made at run time, so the upstream form files
   need only minimal modifications.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.
}

unit uTCStyle;

{$mode objfpc}{$H+}

interface

uses
  Forms;

{en
   Applies the Total Commander style to the main form.
   Called after each update of the main window view.
}
procedure TCStyleUpdateMainForm(AForm: TCustomForm);

{en
   Returns the path as Total Commander displays it: with a lower case
   drive letter, e.g. "c:\Windows\".
}
function TCStyleDisplayPath(const APath: String): String;

implementation

uses
  Classes, SysUtils, Controls, Graphics, Buttons, Math, Menus, ExtCtrls, StdCtrls,
  ComCtrls, ToolWin, Themes, KASToolBar, KASToolPanel, fMain, uLng;

const
  // Width of the drop down arrow part of the drive combo box
  DRIVE_COMBO_ARROW = 20;
  // Windows theme parts and states of the combo box (vsstyle.h)
  CP_READONLY = 5;
  CP_DROPDOWNBUTTONRIGHT = 6;
  CBRO_NORMAL = 1;
  CBRO_HOT = 2;
  CBRO_PRESSED = 3;

type

  TSpeedButtonAccess = class(TSpeedButton);

  { TTCStyleHelper }

  TTCStyleHelper = class(TComponent)
  private
    FForm: TfrmMain;
  public
    procedure DriveComboPaint(Sender: TObject);
    procedure SeparatorPaint(Sender: TObject);
    procedure FunctionKeyPaint(Sender: TObject);
    procedure KeysResize(Sender: TObject);
    procedure StartMenuClick(Sender: TObject);
  end;

{ TTCStyleHelper }

procedure TTCStyleHelper.DriveComboPaint(Sender: TObject);
var
  R: TRect;
  X, Y: Integer;
  Button: TSpeedButton absolute Sender;
  Details: TThemedElementDetails;
begin
  // Paint over the button like a read only combo box
  R:= Button.ClientRect;
  with Button.Canvas do
  begin
    if ThemeServices.ThemesEnabled then
    begin
      Brush.Color:= Button.Parent.Brush.Color;
      FillRect(R);
      Details.Element:= teComboBox;
      Details.Part:= CP_READONLY;
      if TSpeedButtonAccess(Button).FState in [bsDown, bsExclusive] then
        Details.State:= CBRO_PRESSED
      else if Button.MouseInClient then
        Details.State:= CBRO_HOT
      else begin
        Details.State:= CBRO_NORMAL;
      end;
      ThemeServices.DrawElement(Handle, Details, R);
      Details.Part:= CP_DROPDOWNBUTTONRIGHT;
      Details.State:= CBRO_NORMAL;
      ThemeServices.DrawElement(Handle, Details,
                                Rect(R.Right - DRIVE_COMBO_ARROW, R.Top, R.Right, R.Bottom));
    end
    else begin
      Brush.Color:= clWindow;
      Pen.Color:= clBtnShadow;
      Rectangle(R);
      Details:= ThemeServices.GetElementDetails(tcDropDownButtonNormal);
      ThemeServices.DrawElement(Handle, Details,
                                Rect(R.Right - DRIVE_COMBO_ARROW, R.Top + 1, R.Right - 1, R.Bottom - 1));
    end;

    X:= Button.Scale96ToForm(4);
    if Assigned(Button.Images) and (Button.ImageIndex >= 0) then
    begin
      Y:= (Button.Height - Button.ImageWidth) div 2;
      Button.Images.DrawForControl(Button.Canvas, X, Y, Button.ImageIndex,
                                   Button.ImageWidth, Button, Button.Enabled);
      Inc(X, Button.ImageWidth + Button.Scale96ToForm(5));
    end;

    Brush.Style:= bsClear;
    Font:= Button.Font;
    Font.Color:= clWindowText;
    Y:= (Button.Height - TextHeight(Button.Caption)) div 2;
    TextOut(X, Y, Button.Caption);
  end;
end;

procedure TTCStyleHelper.SeparatorPaint(Sender: TObject);
var
  X: Integer;
  Button: TSpeedButton absolute Sender;
begin
  with Button.Canvas do
  begin
    Brush.Color:= Button.Parent.Brush.Color;
    FillRect(Button.ClientRect);
    X:= Button.Width div 2;
    Pen.Color:= clBtnShadow;
    Line(X, 2, X, Button.Height - 2);
  end;
end;

procedure TTCStyleHelper.FunctionKeyPaint(Sender: TObject);
var
  X: Integer;
  Button: TSpeedButton absolute Sender;
begin
  // Separator line on the right side, except the last button
  if Button.Left + Button.Width < Button.Parent.ClientWidth - 1 then
  begin
    X:= Button.Width - 1;
    Button.Canvas.Pen.Color:= clBtnShadow;
    Button.Canvas.Line(X, Button.Scale96ToForm(5), X, Button.Height - Button.Scale96ToForm(2));
  end;
end;

procedure TTCStyleHelper.KeysResize(Sender: TObject);
var
  I, N, X, W: Integer;
  Panel: TWinControl absolute Sender;
  Buttons: array of TControl = nil;
begin
  // All function key buttons have equal width
  for I:= 0 to Panel.ControlCount - 1 do
  begin
    if Panel.Controls[I].Visible then
    begin
      SetLength(Buttons, Length(Buttons) + 1);
      Buttons[High(Buttons)]:= Panel.Controls[I];
    end;
  end;
  N:= Length(Buttons);
  if N = 0 then Exit;
  X:= 0;
  for I:= 0 to N - 1 do
  begin
    W:= (Panel.ClientWidth * (I + 1)) div N - X;
    Buttons[I].SetBounds(X, 0, W, Panel.ClientHeight);
    Inc(X, W);
  end;
end;

procedure TTCStyleHelper.StartMenuClick(Sender: TObject);
begin
  FForm.Commands.cm_ConfigToolbars([]);
end;

var
  Helper: TTCStyleHelper = nil;

procedure UpdateMainMenu(F: TfrmMain);
var
  I: Integer;
  mnuStart, miStartConfig: TMenuItem;
begin
  // Total Commander has no tabs and favorite tabs menu
  F.mnuTabs.Visible:= False;
  F.mnuFavoriteTabs.Visible:= False;

  // "Start" menu before "Help"
  mnuStart:= TMenuItem(F.FindComponent('mnuTCStart'));
  if (mnuStart = nil) then
  begin
    mnuStart:= TMenuItem.Create(F);
    mnuStart.Name:= 'mnuTCStart';
    mnuStart.Caption:= rsMnuTCStart;
    miStartConfig:= TMenuItem.Create(mnuStart);
    miStartConfig.Caption:= rsMnuTCStartConfig;
    miStartConfig.OnClick:= @Helper.StartMenuClick;
    mnuStart.Add(miStartConfig);
    I:= F.mnuMain.Items.IndexOf(F.mnuHelp);
    F.mnuMain.Items.Insert(I, mnuStart);
  end;

  // "Help" on the right side of the menu bar
  F.mnuHelp.RightJustify:= True;
end;

procedure UpdateToolbars(F: TfrmMain);
begin
  // Toolbars have white background with a line above and below
  F.MainToolbar.Color:= clWindow;
  F.MainToolbar.EdgeBorders:= [ebTop];
  F.pnlDisk.Color:= clWindow;
  F.pnlDskLeft.Color:= clWindow;
  F.pnlDskRight.Color:= clWindow;
  F.dskLeft.Color:= clWindow;
  F.dskRight.Color:= clWindow;
end;

procedure UpdateDriveTools(Drive, Hotlist, Home, EqualPanel: TSpeedButton);
begin
  // Drive combo box, free space, separator, "\" and ".." buttons
  Drive.OnPaint:= @Helper.DriveComboPaint;
  Drive.Constraints.MinHeight:= Drive.Scale96ToForm(22);
  Drive.Constraints.MaxHeight:= Drive.Scale96ToForm(22);
  Hotlist.OnPaint:= @Helper.SeparatorPaint;
  Hotlist.Caption:= EmptyStr;
  Hotlist.Width:= Hotlist.Scale96ToForm(9);
  Hotlist.Enabled:= False;
  Home.Visible:= False;
  EqualPanel.Visible:= False;
end;

procedure UpdateFunctionKeys(F: TfrmMain);
var
  I: Integer;
begin
  F.pnlKeys.ChildSizing.Layout:= cclNone;
  F.pnlKeys.Height:= F.Scale96ToForm(25);
  F.pnlKeys.OnResize:= @Helper.KeysResize;
  for I:= 0 to F.pnlKeys.ControlCount - 1 do
  begin
    if F.pnlKeys.Controls[I] is TSpeedButton then
      TSpeedButton(F.pnlKeys.Controls[I]).OnPaint:= @Helper.FunctionKeyPaint;
  end;
  Helper.KeysResize(F.pnlKeys);
end;

function TCStyleDisplayPath(const APath: String): String;
begin
  Result := APath;
{$IFDEF MSWINDOWS}
  if (Length(Result) >= 2) and (Result[2] = ':') and (Result[1] in ['A'..'Z']) then
    Result[1] := LowerCase(Result[1]);
{$ENDIF}
end;

procedure TCStyleUpdateMainForm(AForm: TCustomForm);
var
  F: TfrmMain absolute AForm;
begin
  if (Helper = nil) then
  begin
    Helper:= TTCStyleHelper.Create(AForm);
    Helper.FForm:= F;
  end;
  UpdateMainMenu(F);
  UpdateToolbars(F);
  UpdateDriveTools(F.btnLeftDrive, F.btnLeftDirectoryHotlist, F.btnLeftHome, F.btnLeftEqualRight);
  UpdateDriveTools(F.btnRightDrive, F.btnRightDirectoryHotlist, F.btnRightHome, F.btnRightEqualLeft);
  UpdateFunctionKeys(F);
end;

end.
