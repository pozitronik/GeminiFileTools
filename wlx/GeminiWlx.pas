/// <summary>
///   WLX lister plugin implementation for Gemini conversation files.
///   Renders Gemini conversations as HTML in an embedded WebView2 control.
///   Implements both Unicode and ANSI variants of the WLX API.
/// </summary>
unit GeminiWlx;

interface

uses
	Winapi.Windows,
	Winapi.Messages,
	Winapi.ActiveX,
	Winapi.WebView2,
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.IniFiles,
	WlxApi,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Parser,
	GeminiFile.Extractor,
	GeminiFile,
	GeminiFile.Formatter.Intf,
	GeminiFile.Formatter.Html;

type
	TListerConfig = record
		HideEmptyBlocks: Boolean;
		CombineBlocks: Boolean;
		RenderMarkdown: Boolean;
		DefaultFullWidth: Boolean;
		DefaultExpandThinking: Boolean;
		UserDataFolder: string;
		AllowContextMenu: Boolean;
		AllowDevTools: Boolean;
	end;

	/// <summary>
	///   Per-window state for a single lister instance.
	///   Pointer stored via SetWindowLongPtr(GWLP_USERDATA).
	/// </summary>
	TGeminiListerWindow = class
	private
		FParentWin: HWND;
		FPluginWin: HWND;
		FStatusLabel: HWND;
		FEnvironment: ICoreWebView2Environment;
		FController: ICoreWebView2Controller;
		FWebView: ICoreWebView2;
		FTempHtmlPath: string;
		FFileName: string;
		FWebViewReady: Boolean;
		FPendingNavigation: string;
		procedure CleanupTempFile;
		function GenerateHtml(const AFileName: string): string;
		procedure NavigateToFile(const AHtmlPath: string);
		procedure ShowStatus(const AMessage: string);
		procedure HideStatus;
	public
		constructor Create(AParentWin: HWND; APluginWin: HWND);
		destructor Destroy; override;
		procedure InitWebView2;
		procedure LoadFile(const AFileName: string);
		procedure ResizeWebView;
		property PluginWin: HWND read FPluginWin;
		property WebViewReady: Boolean read FWebViewReady;
	end;

	/// <summary>
	///   COM callback for WebView2 environment creation completion.
	/// </summary>
	TEnvironmentCompletedHandler = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
	private
		FOwner: TGeminiListerWindow;
	public
		constructor Create(AOwner: TGeminiListerWindow);
		function Invoke(errorCode: HResult; const createdEnvironment: ICoreWebView2Environment): HResult; stdcall;
	end;

	/// <summary>
	///   COM callback for WebView2 controller creation completion.
	/// </summary>
	TControllerCompletedHandler = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)
	private
		FOwner: TGeminiListerWindow;
	public
		constructor Create(AOwner: TGeminiListerWindow);
		function Invoke(errorCode: HResult; const createdController: ICoreWebView2Controller): HResult; stdcall;
	end;

	/// <summary>
	///   Intercepts keyboard events before WebView2 processes them.
	///   Forwards unmodified keys (Esc, N, P, etc.) to TC's parent window
	///   so lister hotkeys keep working when WebView2 has focus.
	/// </summary>
	TAcceleratorKeyPressedHandler = class(TInterfacedObject, ICoreWebView2AcceleratorKeyPressedEventHandler)
	private
		FParentWin: HWND;
	public
		constructor Create(AParentWin: HWND);
		function Invoke(const sender: ICoreWebView2Controller;
			const args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
	end;

function GetListerConfig: TListerConfig;
procedure DebugLog(const ACategory, AMessage: string);

// --- Exported WLX functions ---

// Unicode (primary)
function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadNextW(ParentWin: HWND; ListWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): Integer; stdcall;
function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;

// ANSI (compatibility)
function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadNext(ParentWin: HWND; ListWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): Integer; stdcall;
function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;

// Common
procedure ListCloseWindow(ListWin: HWND); stdcall;
procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;

implementation

uses
	System.AnsiStrings,
	GeminiFile.Formatter.Utils;

const
	GEMINI_LISTER_CLASS = 'GeminiListerClass';

	/// Default plugin configuration values
	DEF_HideEmptyBlocks = True;
	DEF_CombineBlocks = False;
	DEF_RenderMarkdown = True;
	DEF_DefaultFullWidth = False;
	DEF_DefaultExpandThinking = False;
	DEF_AllowContextMenu = False;
	DEF_AllowDevTools = False;

type
	/// <summary>
	///   Function signature for CreateCoreWebView2EnvironmentWithOptions
	///   exported by WebView2Loader.dll.
	/// </summary>
	TCreateCoreWebView2EnvironmentWithOptionsFunc = function(browserExecutableFolder: LPCWSTR; UserDataFolder: LPCWSTR; const environmentOptions: ICoreWebView2EnvironmentOptions; const environmentCreatedHandler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HResult; stdcall;

var
	GClassRegistered: Boolean;
	GCustomCSS: string;
	GCustomCSSLoaded: Boolean;
	GListerConfig: TListerConfig;
	GListerConfigLoaded: Boolean;
	GLoaderHandle: HMODULE;
	GCreateEnvironment: TCreateCoreWebView2EnvironmentWithOptionsFunc;
	GComInitialized: Boolean;
	GDebugLogPath: string;

	/// <summary>
	///   Appends a timestamped line to the debug log file next to the DLL.
	/// </summary>
procedure DebugLog(const ACategory, AMessage: string);
var
	LFile: TextFile;
	LStamp: string;
begin
	if GDebugLogPath = '' then
		Exit;
	try
		LStamp := FormatDateTime('hh:nn:ss.zzz', Now);
		AssignFile(LFile, GDebugLogPath);
		if FileExists(GDebugLogPath) then
			Append(LFile)
		else
			Rewrite(LFile);
		WriteLn(LFile, LStamp + ' [' + ACategory + '] ' + AMessage);
		CloseFile(LFile);
	except
		// Logging must never crash the host process
	end;
end;

/// <summary>
///   Returns the directory containing the plugin DLL.
/// </summary>
function GetPluginDir: string;
var
	LDllPath: array [0 .. MAX_PATH] of Char;
begin
	if GetModuleFileName(HInstance, LDllPath, MAX_PATH + 1) > 0 then
		Result := TPath.GetDirectoryName(LDllPath)
	else
		Result := '';
end;

/// <summary>
///   Returns custom CSS content from gemini.css located next to the plugin DLL.
///   Caches the result on first call; returns empty string if file not found.
/// </summary>
function GetCustomCSS: string;
var
	LCssPath: string;
begin
	if not GCustomCSSLoaded then
	begin
		GCustomCSSLoaded := True;
		GCustomCSS := '';
		LCssPath := TPath.Combine(GetPluginDir, 'gemini.css');
		if TFile.Exists(LCssPath) then
			GCustomCSS := TFile.ReadAllText(LCssPath, TEncoding.UTF8);
	end;
	Result := GCustomCSS;
end;

function GetListerConfig: TListerConfig;
var
	LIniPath: string;
	LIni: TIniFile;
begin
	if not GListerConfigLoaded then
	begin
		GListerConfigLoaded := True;
		GListerConfig := Default (TListerConfig);
		GListerConfig.HideEmptyBlocks := DEF_HideEmptyBlocks;
		GListerConfig.CombineBlocks := DEF_CombineBlocks;
		GListerConfig.RenderMarkdown := DEF_RenderMarkdown;
		GListerConfig.DefaultFullWidth := DEF_DefaultFullWidth;
		GListerConfig.DefaultExpandThinking := DEF_DefaultExpandThinking;
		GListerConfig.AllowContextMenu := DEF_AllowContextMenu;
		GListerConfig.AllowDevTools := DEF_AllowDevTools;

		LIniPath := TPath.Combine(GetPluginDir, 'gemini.ini');
		if TFile.Exists(LIniPath) then
		begin
			LIni := TIniFile.Create(LIniPath);
			try
				GListerConfig.HideEmptyBlocks := LIni.ReadBool('General', 'HideEmptyBlocks', DEF_HideEmptyBlocks);
				GListerConfig.CombineBlocks := LIni.ReadBool('General', 'CombineBlocks', DEF_CombineBlocks);
				GListerConfig.RenderMarkdown := LIni.ReadBool('General', 'RenderMarkdown', DEF_RenderMarkdown);
				GListerConfig.DefaultFullWidth := LIni.ReadBool('HtmlDefaults', 'DefaultFullWidth', DEF_DefaultFullWidth);
				GListerConfig.DefaultExpandThinking := LIni.ReadBool('HtmlDefaults', 'DefaultExpandThinking', DEF_DefaultExpandThinking);
				GListerConfig.UserDataFolder := LIni.ReadString('WebView2', 'UserDataFolder', '');
				GListerConfig.AllowContextMenu := LIni.ReadBool('WebView2', 'AllowContextMenu', DEF_AllowContextMenu);
				GListerConfig.AllowDevTools := LIni.ReadBool('WebView2', 'AllowDevTools', DEF_AllowDevTools);
			finally
				LIni.Free;
			end;
		end;
	end;
	Result := GListerConfig;
end;

/// <summary>
///   Returns the WebView2 user data folder path.
///   Uses config value if set, otherwise %TEMP%\gemini_wlx.
/// </summary>
function GetUserDataFolder: string;
var
	LConfig: TListerConfig;
begin
	LConfig := GetListerConfig;
	if LConfig.UserDataFolder <> '' then
		Result := LConfig.UserDataFolder
	else
		Result := TPath.Combine(TPath.GetTempPath, 'gemini_wlx');
end;

/// <summary>
///   Ensures COM is initialized for WebView2. Safe to call multiple times.
/// </summary>
procedure EnsureComInitialized;
var
	LHr: HResult;
begin
	if GComInitialized then
		Exit;
	LHr := OleInitialize(nil);
	// S_OK = initialized, S_FALSE = already initialized -- both are fine
	GComInitialized := Succeeded(LHr);
	DebugLog('COM', 'OleInitialize result=0x' + IntToHex(LHr, 8) + ' success=' + BoolToStr(GComInitialized, True));
end;

/// <summary>
///   Dynamically loads WebView2Loader.dll from the architecture-specific
///   subfolder next to the plugin DLL, or from the plugin directory itself.
/// </summary>
function EnsureWebView2Loaded: Boolean;
var
	LSubDir, LLoaderPath: string;
begin
	if GLoaderHandle <> 0 then
		Exit(True);

{$IFDEF WIN64}
	LSubDir := 'webview2x64';
{$ELSE}
	LSubDir := 'webview2x32';
{$ENDIF}
	// Try architecture-specific subfolder first
	LLoaderPath := TPath.Combine(TPath.Combine(GetPluginDir, LSubDir), 'WebView2Loader.dll');
	DebugLog('WebView2', 'Trying subfolder: ' + LLoaderPath);
	if TFile.Exists(LLoaderPath) then
		GLoaderHandle := LoadLibrary(PChar(LLoaderPath));

	// Fallback: plugin directory
	if GLoaderHandle = 0 then
	begin
		LLoaderPath := TPath.Combine(GetPluginDir, 'WebView2Loader.dll');
		DebugLog('WebView2', 'Trying plugin dir: ' + LLoaderPath);
		if TFile.Exists(LLoaderPath) then
			GLoaderHandle := LoadLibrary(PChar(LLoaderPath));
	end;

	// Fallback: standard Windows DLL search path (system-installed)
	if GLoaderHandle = 0 then
	begin
		DebugLog('WebView2', 'Trying system search path');
		GLoaderHandle := LoadLibrary('WebView2Loader.dll');
	end;

	if GLoaderHandle = 0 then
	begin
		DebugLog('WebView2', 'FAILED: WebView2Loader.dll not found anywhere, LastError=' + IntToStr(GetLastError));
		Exit(False);
	end;

	DebugLog('WebView2', 'Loaded WebView2Loader.dll, handle=0x' + IntToHex(GLoaderHandle, 8));

	GCreateEnvironment := GetProcAddress(GLoaderHandle, 'CreateCoreWebView2EnvironmentWithOptions');
	if not Assigned(GCreateEnvironment) then
	begin
		DebugLog('WebView2', 'FAILED: GetProcAddress for CreateCoreWebView2EnvironmentWithOptions');
		FreeLibrary(GLoaderHandle);
		GLoaderHandle := 0;
		Exit(False);
	end;

	DebugLog('WebView2', 'CreateCoreWebView2EnvironmentWithOptions resolved');
	Result := True;
end;

// ========================================================================
// Window procedure
// ========================================================================

function ListerWndProc(Wnd: HWND; Msg: UINT; wParam: wParam; lParam: lParam): LRESULT; stdcall;
var
	LWindow: TGeminiListerWindow;
begin
	LWindow := TGeminiListerWindow(GetWindowLongPtr(Wnd, GWLP_USERDATA));

	case Msg of
		WM_SIZE:
			begin
				if (LWindow <> nil) then
					LWindow.ResizeWebView;
				Result := 0;
			end;
		WM_SETFOCUS:
			begin
				if (LWindow <> nil) and (LWindow.FController <> nil) then
					LWindow.FController.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
				Result := 0;
			end;
		else
			Result := DefWindowProc(Wnd, Msg, wParam, lParam);
	end;
end;

procedure RegisterListerClass;
var
	LWndClass: TWndClass;
begin
	if GClassRegistered then
		Exit;

	FillChar(LWndClass, SizeOf(LWndClass), 0);
	LWndClass.lpfnWndProc := @ListerWndProc;
	LWndClass.HInstance := HInstance;
	LWndClass.lpszClassName := GEMINI_LISTER_CLASS;
	LWndClass.hCursor := LoadCursor(0, IDC_ARROW);
	LWndClass.hbrBackground := COLOR_WINDOW + 1;

	if Winapi.Windows.RegisterClass(LWndClass) <> 0 then
		GClassRegistered := True;
end;

// ========================================================================
// TGeminiListerWindow
// ========================================================================

constructor TGeminiListerWindow.Create(AParentWin: HWND; APluginWin: HWND);
begin
	inherited Create;
	FParentWin := AParentWin;
	FPluginWin := APluginWin;
	FWebViewReady := False;

	// Create a status label for loading/error messages
	FStatusLabel := CreateWindowEx(0, 'STATIC', 'Loading...', WS_CHILD or WS_VISIBLE or SS_CENTER or SS_CENTERIMAGE, 0, 0, 1, 1, FPluginWin, 0, HInstance, nil);
	DebugLog('Window', 'Created, parent=0x' + IntToHex(AParentWin, 8) + ' plugin=0x' + IntToHex(APluginWin, 8));
end;

destructor TGeminiListerWindow.Destroy;
begin
	DebugLog('Window', 'Destroy enter, plugin=0x' + IntToHex(FPluginWin, 8));

	if FController <> nil then
	begin
		DebugLog('Window', 'Closing WebView2 controller');
		FController.Close;
	end;

	FWebView := nil;
	FController := nil;
	FEnvironment := nil;

	CleanupTempFile;
	DebugLog('Window', 'Destroy leave');
	inherited;
end;

procedure TGeminiListerWindow.ShowStatus(const AMessage: string);
var
	LRect: TRect;
begin
	if FStatusLabel <> 0 then
	begin
		GetClientRect(FPluginWin, LRect);
		SetWindowPos(FStatusLabel, 0, 0, 0, LRect.Right, LRect.Bottom, SWP_NOZORDER);
		SetWindowText(FStatusLabel, PChar(AMessage));
		ShowWindow(FStatusLabel, SW_SHOW);
	end;
end;

procedure TGeminiListerWindow.HideStatus;
begin
	if FStatusLabel <> 0 then
		ShowWindow(FStatusLabel, SW_HIDE);
end;

procedure TGeminiListerWindow.CleanupTempFile;
begin
	if (FTempHtmlPath <> '') and TFile.Exists(FTempHtmlPath) then
	begin
		try
			TFile.Delete(FTempHtmlPath);
		except
			// Ignore deletion failures (file may be locked by WebView2)
		end;
	end;
	FTempHtmlPath := '';
end;

function TGeminiListerWindow.GenerateHtml(const AFileName: string): string;
var
	LGeminiFile: TGeminiFile;
	LResources: TArray<TGeminiResource>;
	LResourceInfos: TArray<TFormatterResourceInfo>;
	LHtmlFmt: TGeminiHtmlFormatter;
	LFmt: IGeminiFormatter;
	LStream: TMemoryStream;
	LConfig: TListerConfig;
	LTempPath: string;
	I, LPadWidth: Integer;
begin
	Result := '';
	LConfig := GetListerConfig;

	LGeminiFile := TGeminiFile.Create;
	try
		LGeminiFile.LoadFromFile(AFileName);

		LResources := LGeminiFile.GetResources;

		// Build resource infos with base64 data for embedded mode
		SetLength(LResourceInfos, Length(LResources));
		LPadWidth := ResourcePadWidth(Length(LResources));
		for I := 0 to High(LResources) do
		begin
			LResourceInfos[I].FileName := Format('resources/resource_%.*d%s', [LPadWidth, I, LResources[I].GetFileExtension]);
			LResourceInfos[I].MimeType := LResources[I].MimeType;
			LResourceInfos[I].Base64Data := LResources[I].Base64Data;
			LResourceInfos[I].DecodedSize := LResources[I].DecodedSize;
			LResourceInfos[I].ChunkIndex := LResources[I].ChunkIndex;
			LResourceInfos[I].IsThinking := False;
			if LResources[I].ChunkIndex < LGeminiFile.Chunks.Count then
				LResourceInfos[I].IsThinking := LGeminiFile.Chunks[LResources[I].ChunkIndex].IsThought;
		end;

		// Generate embedded HTML
		LHtmlFmt := TGeminiHtmlFormatter.Create(True, GetCustomCSS);
		LHtmlFmt.SourceFileName := TPath.GetFileNameWithoutExtension(AFileName);
		LHtmlFmt.HideEmptyBlocks := LConfig.HideEmptyBlocks;
		LHtmlFmt.CombineBlocks := LConfig.CombineBlocks;
		LHtmlFmt.RenderMarkdown := LConfig.RenderMarkdown;
		LHtmlFmt.DefaultFullWidth := LConfig.DefaultFullWidth;
		LHtmlFmt.DefaultExpandThinking := LConfig.DefaultExpandThinking;
		LFmt := LHtmlFmt;

		LStream := TMemoryStream.Create;
		try
			LFmt.FormatToStream(LStream, LGeminiFile.Chunks, LGeminiFile.SystemInstruction, LGeminiFile.RunSettings, LResourceInfos);

			// Write to temp file
			LTempPath := TPath.Combine(TPath.GetTempPath, 'gemini_wlx_' + TPath.GetGUIDFileName + '.html');
			LStream.Position := 0;
			LStream.SaveToFile(LTempPath);
			Result := LTempPath;
		finally
			LStream.Free;
		end;
	finally
		LGeminiFile.Free;
	end;
end;

procedure TGeminiListerWindow.NavigateToFile(const AHtmlPath: string);
var
	LUrl: string;
begin
	DebugLog('Navigate', 'path=' + AHtmlPath + ' webview=' + BoolToStr(FWebView <> nil, True));
	if (FWebView <> nil) and (AHtmlPath <> '') then
	begin
		LUrl := 'file:///' + StringReplace(AHtmlPath, '\', '/', [rfReplaceAll]);
		FWebView.Navigate(PWideChar(LUrl));
		DebugLog('Navigate', 'Navigate called with url=' + LUrl);
		HideStatus;
	end;
end;

procedure TGeminiListerWindow.LoadFile(const AFileName: string);
var
	LNewTempPath: string;
begin
	DebugLog('LoadFile', 'enter, file=' + AFileName);
	FFileName := AFileName;

	ShowStatus('Parsing ' + TPath.GetFileName(AFileName) + '...');

	try
		LNewTempPath := GenerateHtml(AFileName);
	except
		on E: Exception do
		begin
			DebugLog('LoadFile', 'EXCEPTION in GenerateHtml: ' + E.Message);
			ShowStatus('Error: ' + E.Message);
			Exit;
		end;
	end;

	if LNewTempPath = '' then
	begin
		DebugLog('LoadFile', 'GenerateHtml returned empty path');
		ShowStatus('Error: failed to generate HTML');
		Exit;
	end;

	DebugLog('LoadFile', 'HTML generated: ' + LNewTempPath);

	// Cleanup previous temp file
	CleanupTempFile;
	FTempHtmlPath := LNewTempPath;

	if FWebViewReady then
	begin
		DebugLog('LoadFile', 'WebView ready, navigating immediately');
		NavigateToFile(FTempHtmlPath);
	end else begin
		DebugLog('LoadFile', 'WebView not ready, queuing pending navigation');
		FPendingNavigation := FTempHtmlPath;
		ShowStatus('Initializing WebView2...');
	end;
end;

procedure TGeminiListerWindow.InitWebView2;
var
	LHandler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
	LUserData: string;
	LHr: HResult;
begin
	DebugLog('InitWebView2', 'enter');
	EnsureComInitialized;

	if not EnsureWebView2Loaded then
	begin
		DebugLog('InitWebView2', 'FAILED: WebView2Loader.dll not found');
		ShowStatus('Error: WebView2Loader.dll not found. Install WebView2 SDK or place the DLL next to the plugin.');
		Exit;
	end;

	LUserData := GetUserDataFolder;
	DebugLog('InitWebView2', 'UserDataFolder=' + LUserData);
	LHandler := TEnvironmentCompletedHandler.Create(Self);
	LHr := GCreateEnvironment(nil, PWideChar(LUserData), nil, LHandler);
	DebugLog('InitWebView2', 'GCreateEnvironment returned 0x' + IntToHex(LHr, 8));
	if Failed(LHr) then
		ShowStatus('Error: WebView2 init failed (0x' + IntToHex(LHr, 8) + '). Is Edge WebView2 Runtime installed?');
end;

procedure TGeminiListerWindow.ResizeWebView;
var
	LRect: Winapi.WebView2.tagRECT;
begin
	if FController <> nil then
	begin
		GetClientRect(FPluginWin, Winapi.Windows.TRect(LRect));
		FController.Set_Bounds(LRect);
	end;
end;

// ========================================================================
// TEnvironmentCompletedHandler
// ========================================================================

constructor TEnvironmentCompletedHandler.Create(AOwner: TGeminiListerWindow);
begin
	inherited Create;
	FOwner := AOwner;
end;

function TEnvironmentCompletedHandler.Invoke(errorCode: HResult; const createdEnvironment: ICoreWebView2Environment): HResult; stdcall;
var
	LHandler: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
begin
	DebugLog('EnvCallback', 'Invoke errorCode=0x' + IntToHex(errorCode, 8) + ' env=' + BoolToStr(createdEnvironment <> nil, True));
	if Failed(errorCode) or (createdEnvironment = nil) then
	begin
		FOwner.ShowStatus('Error: WebView2 environment creation failed (0x' + IntToHex(errorCode, 8) + ')');
		Exit(errorCode);
	end;

	FOwner.FEnvironment := createdEnvironment;
	LHandler := TControllerCompletedHandler.Create(FOwner);
	Result := createdEnvironment.CreateCoreWebView2Controller(FOwner.FPluginWin, LHandler);
	DebugLog('EnvCallback', 'CreateCoreWebView2Controller returned 0x' + IntToHex(Result, 8));
	if Failed(Result) then
		FOwner.ShowStatus('Error: WebView2 controller creation failed (0x' + IntToHex(Result, 8) + ')');
end;

// ========================================================================
// TControllerCompletedHandler
// ========================================================================

constructor TControllerCompletedHandler.Create(AOwner: TGeminiListerWindow);
begin
	inherited Create;
	FOwner := AOwner;
end;

function TControllerCompletedHandler.Invoke(errorCode: HResult; const createdController: ICoreWebView2Controller): HResult; stdcall;
var
	LSettings: ICoreWebView2Settings;
	LConfig: TListerConfig;
	LRect: Winapi.WebView2.tagRECT;
begin
	DebugLog('CtrlCallback', 'Invoke errorCode=0x' + IntToHex(errorCode, 8) + ' ctrl=' + BoolToStr(createdController <> nil, True));
	if Failed(errorCode) or (createdController = nil) then
	begin
		FOwner.ShowStatus('Error: WebView2 controller callback failed (0x' + IntToHex(errorCode, 8) + ')');
		Exit(errorCode);
	end;

	FOwner.FController := createdController;
	createdController.Get_CoreWebView2(FOwner.FWebView);
	DebugLog('CtrlCallback', 'Got CoreWebView2, webview=' + BoolToStr(FOwner.FWebView <> nil, True));

	// Configure WebView2 settings
	LConfig := GetListerConfig;
	if Succeeded(FOwner.FWebView.Get_Settings(LSettings)) then
	begin
		if LConfig.AllowDevTools then
			LSettings.Set_AreDevToolsEnabled(1)
		else
			LSettings.Set_AreDevToolsEnabled(0);
		if LConfig.AllowContextMenu then
			LSettings.Set_AreDefaultContextMenusEnabled(1)
		else
			LSettings.Set_AreDefaultContextMenusEnabled(0);
		LSettings.Set_IsScriptEnabled(1);
		LSettings.Set_IsZoomControlEnabled(1);
		LSettings.Set_IsStatusBarEnabled(0);
	end;

	// Forward unmodified keys from WebView2 to TC parent window
	var LToken: EventRegistrationToken;
	createdController.add_AcceleratorKeyPressed(
		TAcceleratorKeyPressedHandler.Create(FOwner.FParentWin), LToken);
	DebugLog('CtrlCallback', 'AcceleratorKeyPressed handler registered');

	// Size the WebView2 to fill the plugin window
	GetClientRect(FOwner.FPluginWin, Winapi.Windows.TRect(LRect));
	createdController.Set_Bounds(LRect);
	createdController.Set_IsVisible(1);

	FOwner.FWebViewReady := True;
	DebugLog('CtrlCallback', 'WebView2 ready, isVisible=1');

	// Navigate to pending content if file was loaded before WebView2 was ready
	if FOwner.FPendingNavigation <> '' then
	begin
		DebugLog('CtrlCallback', 'Navigating to pending: ' + FOwner.FPendingNavigation);
		FOwner.NavigateToFile(FOwner.FPendingNavigation);
		FOwner.FPendingNavigation := '';
	end;

	Result := S_OK;
end;

// ========================================================================
// TAcceleratorKeyPressedHandler
// ========================================================================

constructor TAcceleratorKeyPressedHandler.Create(AParentWin: HWND);
begin
	inherited Create;
	FParentWin := AParentWin;
end;

function TAcceleratorKeyPressedHandler.Invoke(const sender: ICoreWebView2Controller;
	const args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
var
	LKind: COREWEBVIEW2_KEY_EVENT_KIND;
	LKey: SYSUINT;
begin
	Result := S_OK;

	if Failed(args.Get_KeyEventKind(LKind)) then
		Exit;
	// Only intercept key-down events
	if LKind <> COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN then
		Exit;

	// Let WebView2 handle keys when any modifier is held (Ctrl+C, Ctrl+A, etc.)
	if (GetKeyState(VK_CONTROL) < 0) or (GetKeyState(VK_MENU) < 0) or (GetKeyState(VK_SHIFT) < 0) then
		Exit;

	if Failed(args.Get_VirtualKey(LKey)) then
		Exit;

	// Forward unmodified keys to TC parent so lister hotkeys work
	args.Set_Handled(1);
	PostMessage(FParentWin, WM_KEYDOWN, LKey, 0);
end;

// ========================================================================
// Exported functions -- Unicode (primary)
// ========================================================================

function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
var
	LWindow: TGeminiListerWindow;
	LPluginWin: HWND;
	LRect: TRect;
begin
	DebugLog('ListLoadW', 'enter, file=' + string(FileToLoad) + ' flags=' + IntToStr(ShowFlags));
	Result := 0;

	RegisterListerClass;
	if not GClassRegistered then
	begin
		DebugLog('ListLoadW', 'FAILED: class not registered');
		Exit;
	end;

	GetClientRect(ParentWin, LRect);
	LPluginWin := CreateWindowEx(0, GEMINI_LISTER_CLASS, nil, WS_CHILD or WS_VISIBLE, 0, 0, LRect.Right - LRect.Left, LRect.Bottom - LRect.Top, ParentWin, 0, HInstance, nil);
	if LPluginWin = 0 then
	begin
		DebugLog('ListLoadW', 'FAILED: CreateWindowEx returned 0, LastError=' + IntToStr(GetLastError));
		Exit;
	end;

	LWindow := TGeminiListerWindow.Create(ParentWin, LPluginWin);
	SetWindowLongPtr(LPluginWin, GWLP_USERDATA, NativeInt(LWindow));

	LWindow.LoadFile(string(FileToLoad));
	LWindow.InitWebView2;

	Result := LPluginWin;
	DebugLog('ListLoadW', 'leave, result=0x' + IntToHex(Result, 8));
end;

function ListLoadNextW(ParentWin: HWND; ListWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): Integer; stdcall;
var
	LWindow: TGeminiListerWindow;
begin
	DebugLog('ListLoadNextW', 'enter, file=' + string(FileToLoad));
	Result := LISTPLUGIN_ERROR;
	LWindow := TGeminiListerWindow(GetWindowLongPtr(ListWin, GWLP_USERDATA));
	if LWindow = nil then
	begin
		DebugLog('ListLoadNextW', 'FAILED: window object is nil');
		Exit;
	end;

	try
		LWindow.LoadFile(string(FileToLoad));
		Result := LISTPLUGIN_OK;
	except
		on E: Exception do
		begin
			DebugLog('ListLoadNextW', 'EXCEPTION: ' + E.Message);
			Result := LISTPLUGIN_ERROR;
		end;
	end;
	DebugLog('ListLoadNextW', 'leave, result=' + IntToStr(Result));
end;

function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;
var
	LWindow: TGeminiListerWindow;
	LScript: string;
	LCaseSensitive, LBackwards: Boolean;
begin
	DebugLog('ListSearchTextW', 'search="' + string(SearchString) + '" param=' + IntToStr(SearchParameter));
	Result := LISTPLUGIN_ERROR;
	LWindow := TGeminiListerWindow(GetWindowLongPtr(ListWin, GWLP_USERDATA));
	if (LWindow = nil) or (LWindow.FWebView = nil) then
		Exit;

	LCaseSensitive := (SearchParameter and lcs_matchcase) <> 0;
	LBackwards := (SearchParameter and lcs_backwards) <> 0;

	// Use window.find() for in-page search
	LScript := Format('window.find("%s", %s, %s, false, false, false, false)', [StringReplace(StringReplace(string(SearchString), '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]), LowerCase(BoolToStr(LCaseSensitive, True)), LowerCase(BoolToStr(LBackwards, True))]);

	LWindow.FWebView.ExecuteScript(PWideChar(LScript), nil);
	Result := LISTPLUGIN_OK;
end;

// ========================================================================
// Exported functions -- ANSI (compatibility)
// ========================================================================

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
var
	LWide: WideString;
begin
	LWide := WideString(AnsiString(FileToLoad));
	Result := ListLoadW(ParentWin, PWideChar(LWide), ShowFlags);
end;

function ListLoadNext(ParentWin: HWND; ListWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): Integer; stdcall;
var
	LWide: WideString;
begin
	LWide := WideString(AnsiString(FileToLoad));
	Result := ListLoadNextW(ParentWin, ListWin, PWideChar(LWide), ShowFlags);
end;

function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
var
	LWide: WideString;
begin
	LWide := WideString(AnsiString(SearchString));
	Result := ListSearchTextW(ListWin, PWideChar(LWide), SearchParameter);
end;

// ========================================================================
// Exported functions -- Common
// ========================================================================

procedure ListCloseWindow(ListWin: HWND); stdcall;
var
	LWindow: TGeminiListerWindow;
begin
	DebugLog('ListCloseWindow', 'enter, win=0x' + IntToHex(ListWin, 8));
	LWindow := TGeminiListerWindow(GetWindowLongPtr(ListWin, GWLP_USERDATA));
	SetWindowLongPtr(ListWin, GWLP_USERDATA, 0);
	if LWindow <> nil then
	begin
		DebugLog('ListCloseWindow', 'freeing window object');
		LWindow.Free;
	end;
	DebugLog('ListCloseWindow', 'calling DestroyWindow');
	DestroyWindow(ListWin);
	DebugLog('ListCloseWindow', 'leave');
end;

procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
const
	DETECT = 'FINDI("runSettings") & FINDI("models/gemini")';
begin
	DebugLog('ListGetDetectString', 'called, maxLen=' + IntToStr(MaxLen));
	System.AnsiStrings.StrLCopy(DetectString, PAnsiChar(AnsiString(DETECT)), MaxLen - 1);
end;

procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
begin
	DebugLog('ListSetDefaultParams', 'called, size=' + IntToStr(dps^.Size) + ' ver=' + IntToStr(dps^.PluginInterfaceVersionHi) + '.' + IntToStr(dps^.PluginInterfaceVersionLow));
end;

function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
var
	LWindow: TGeminiListerWindow;
begin
	DebugLog('ListSendCommand', 'cmd=' + IntToStr(Command) + ' param=' + IntToStr(Parameter));
	Result := LISTPLUGIN_ERROR;
	LWindow := TGeminiListerWindow(GetWindowLongPtr(ListWin, GWLP_USERDATA));
	if (LWindow = nil) or (LWindow.FWebView = nil) then
		Exit;

	case Command of
		lc_copy:
			begin
				LWindow.FWebView.ExecuteScript('document.execCommand("copy")', nil);
				Result := LISTPLUGIN_OK;
			end;
		lc_selectall:
			begin
				LWindow.FWebView.ExecuteScript('document.execCommand("selectAll")', nil);
				Result := LISTPLUGIN_OK;
			end;
		else
			Result := LISTPLUGIN_ERROR;
	end;
end;

initialization

GClassRegistered := False;
GLoaderHandle := 0;
GCreateEnvironment := nil;
GComInitialized := False;

// Set up debug log path next to the DLL
GDebugLogPath := TPath.Combine(GetPluginDir, 'gemini_debug.log');
DebugLog('init', 'GeminiWlx initialization, PluginDir=' + GetPluginDir);

finalization

DebugLog('finalization', 'GeminiWlx enter');

// Intentionally NOT calling FreeLibrary(GLoaderHandle) here:
// finalization runs under DLL_PROCESS_DETACH (loader lock held),
// and FreeLibrary is unsafe under the loader lock per MSDN.
// The OS will unmap the DLL when the process exits.
GLoaderHandle := 0;
GCreateEnvironment := nil;

DebugLog('finalization', 'GeminiWlx leave -- RTL finalization follows');

end.
