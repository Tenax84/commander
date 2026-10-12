{
   Double Commander
   -------------------------------------------------------------------------
   Prevents black flashing panels when the main window is restored
   from the minimized state.

   While a window is minimized DWM may discard its redirection surface.
   On restore the window becomes visible before the child controls have
   processed their (low priority) WM_PAINT messages, so the unpainted
   areas are shown black for a moment. To avoid it the window is cloaked
   during the restore, everything is painted synchronously and only then
   the window is uncloaked.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.
}

unit uRestoreFlicker;

{$mode objfpc}{$H+}

interface

uses
  Windows;

procedure InstallRestoreFlickerFix(Wnd: HWND);

implementation

uses
  CommCtrl;

const
  ID_SUB_RESTORE = 2;
  ID_TIMER_UNCLOAK = $DC01;
  DWMWA_CLOAK = 13;
  // Show the window at the latest after this time even if it is still painting
  MAX_CLOAK_TIME = 300;

var
  Cloaked: Boolean = False;
  Minimized: Boolean = False;
  CloakTick: DWORD;

function DwmSetWindowAttribute(hwnd: HWND; dwAttribute: DWORD; pvAttribute: Pointer;
  cbAttribute: DWORD): HRESULT; stdcall; external 'dwmapi.dll';

procedure SetCloak(Wnd: HWND; Value: BOOL);
begin
  DwmSetWindowAttribute(Wnd, DWMWA_CLOAK, @Value, SizeOf(Value));
end;

procedure Uncloak(Wnd: HWND);
begin
  KillTimer(Wnd, ID_TIMER_UNCLOAK);
  Cloaked:= False;
  SetCloak(Wnd, False);
end;

function RestoreWindowProc(Window: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM;
  uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
begin
  case Msg of
    WM_SIZE:
      Minimized:= (wParam = SIZE_MINIMIZED);
    WM_WINDOWPOSCHANGING:
      // Restore or maximize from the minimized state. The minimized
      // style is already removed here, so IsIconic cannot be used.
      if Minimized and (not Cloaked) and (not IsIconic(Window)) and
         IsWindowVisible(Window) and (PWindowPos(lParam)^.flags and SWP_NOSIZE = 0) then
      begin
        Minimized:= False;
        Cloaked:= True;
        CloakTick:= GetTickCount;
        SetCloak(Window, True);
      end;
    WM_WINDOWPOSCHANGED:
      begin
        Result:= DefSubclassProc(Window, Msg, wParam, lParam);
        if Cloaked then
        begin
          if IsIconic(Window) then
            Uncloak(Window)
          else begin
            // WM_TIMER has lower priority than WM_PAINT, so the timer
            // fires only when all controls have finished painting
            RedrawWindow(Window, nil, 0, RDW_INVALIDATE or RDW_ERASE or
                         RDW_FRAME or RDW_ALLCHILDREN);
            SetTimer(Window, ID_TIMER_UNCLOAK, 10, nil);
          end;
        end;
        Exit;
      end;
    WM_TIMER:
      if wParam = ID_TIMER_UNCLOAK then
      begin
        if (not Cloaked) or (GetTickCount - CloakTick > MAX_CLOAK_TIME) or
           (HIWORD(GetQueueStatus(QS_PAINT or QS_POSTMESSAGE or QS_SENDMESSAGE)) = 0) then
        begin
          Uncloak(Window);
        end;
        Exit(0);
      end;
    WM_NCDESTROY:
      begin
        if Cloaked then Uncloak(Window);
        // comctl32 removes the subclass itself on WM_NCDESTROY
      end;
  end;
  Result:= DefSubclassProc(Window, Msg, wParam, lParam);
end;

procedure InstallRestoreFlickerFix(Wnd: HWND);
begin
  SetWindowSubclass(Wnd, @RestoreWindowProc, ID_SUB_RESTORE, 0);
end;

end.
