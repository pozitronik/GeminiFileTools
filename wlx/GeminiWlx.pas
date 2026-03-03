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
		function Invoke(const sender: ICoreWebView2Controller; const args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
	end;

function GetListerConfig: TListerConfig;

// --- Exported WLX functions ---

// Unicode (primary)
function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadNextW(ParentWin: HWND; ListWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): Integer; stdcall;
function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;

// ANSI (compatibility)
function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadNext(ParentWin: HWND; ListWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): Integer; stdcall;
function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;

// Thumbnails
function ListGetPreviewBitmapW(FileToLoad: PWideChar; width, height: Integer; contentbuf: PAnsiChar; contentbuflen: Integer): HBITMAP; stdcall;
function ListGetPreviewBitmap(FileToLoad: PAnsiChar; width, height: Integer; contentbuf: PAnsiChar; contentbuflen: Integer): HBITMAP; stdcall;

// Common
procedure ListCloseWindow(ListWin: HWND); stdcall;
procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;

implementation

uses
	System.AnsiStrings,
	System.Math,
	System.NetEncoding,
	Winapi.Wincodec,
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
	if TFile.Exists(LLoaderPath) then
		GLoaderHandle := LoadLibrary(PChar(LLoaderPath));

	// Fallback: plugin directory
	if GLoaderHandle = 0 then
	begin
		LLoaderPath := TPath.Combine(GetPluginDir, 'WebView2Loader.dll');
		if TFile.Exists(LLoaderPath) then
			GLoaderHandle := LoadLibrary(PChar(LLoaderPath));
	end;

	// Fallback: standard Windows DLL search path (system-installed)
	if GLoaderHandle = 0 then
		GLoaderHandle := LoadLibrary('WebView2Loader.dll');

	if GLoaderHandle = 0 then
		Exit(False);

	GCreateEnvironment := GetProcAddress(GLoaderHandle, 'CreateCoreWebView2EnvironmentWithOptions');
	if not Assigned(GCreateEnvironment) then
	begin
		FreeLibrary(GLoaderHandle);
		GLoaderHandle := 0;
		Exit(False);
	end;

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
end;

destructor TGeminiListerWindow.Destroy;
begin
	if FController <> nil then
		FController.Close;

	FWebView := nil;
	FController := nil;
	FEnvironment := nil;

	CleanupTempFile;
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
	if (FWebView <> nil) and (AHtmlPath <> '') then
	begin
		LUrl := 'file:///' + StringReplace(AHtmlPath, '\', '/', [rfReplaceAll]);
		FWebView.Navigate(PWideChar(LUrl));
		HideStatus;
	end;
end;

procedure TGeminiListerWindow.LoadFile(const AFileName: string);
var
	LNewTempPath: string;
begin
	FFileName := AFileName;

	ShowStatus('Parsing ' + TPath.GetFileName(AFileName) + '...');

	try
		LNewTempPath := GenerateHtml(AFileName);
	except
		on E: Exception do
		begin
			ShowStatus('Error: ' + E.Message);
			Exit;
		end;
	end;

	if LNewTempPath = '' then
	begin
		ShowStatus('Error: failed to generate HTML');
		Exit;
	end;

	// Cleanup previous temp file
	CleanupTempFile;
	FTempHtmlPath := LNewTempPath;

	if FWebViewReady then
		NavigateToFile(FTempHtmlPath)
	else
	begin
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
	EnsureComInitialized;

	if not EnsureWebView2Loaded then
	begin
		ShowStatus('Error: WebView2Loader.dll not found. Install WebView2 SDK or place the DLL next to the plugin.');
		Exit;
	end;

	LUserData := GetUserDataFolder;
	LHandler := TEnvironmentCompletedHandler.Create(Self);
	LHr := GCreateEnvironment(nil, PWideChar(LUserData), nil, LHandler);
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
	if Failed(errorCode) or (createdEnvironment = nil) then
	begin
		FOwner.ShowStatus('Error: WebView2 environment creation failed (0x' + IntToHex(errorCode, 8) + ')');
		Exit(errorCode);
	end;

	FOwner.FEnvironment := createdEnvironment;
	LHandler := TControllerCompletedHandler.Create(FOwner);
	Result := createdEnvironment.CreateCoreWebView2Controller(FOwner.FPluginWin, LHandler);
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
	if Failed(errorCode) or (createdController = nil) then
	begin
		FOwner.ShowStatus('Error: WebView2 controller callback failed (0x' + IntToHex(errorCode, 8) + ')');
		Exit(errorCode);
	end;

	FOwner.FController := createdController;
	createdController.Get_CoreWebView2(FOwner.FWebView);

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
	var
		LToken: EventRegistrationToken;
	createdController.add_AcceleratorKeyPressed(TAcceleratorKeyPressedHandler.Create(FOwner.FParentWin), LToken);

	// Size the WebView2 to fill the plugin window
	GetClientRect(FOwner.FPluginWin, Winapi.Windows.TRect(LRect));
	createdController.Set_Bounds(LRect);
	createdController.Set_IsVisible(1);

	FOwner.FWebViewReady := True;

	// Navigate to pending content if file was loaded before WebView2 was ready
	if FOwner.FPendingNavigation <> '' then
	begin
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

function TAcceleratorKeyPressedHandler.Invoke(const sender: ICoreWebView2Controller; const args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
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
	Result := 0;

	RegisterListerClass;
	if not GClassRegistered then
		Exit;

	GetClientRect(ParentWin, LRect);
	LPluginWin := CreateWindowEx(0, GEMINI_LISTER_CLASS, nil, WS_CHILD or WS_VISIBLE, 0, 0, LRect.Right - LRect.Left, LRect.Bottom - LRect.Top, ParentWin, 0, HInstance, nil);
	if LPluginWin = 0 then
		Exit;

	LWindow := TGeminiListerWindow.Create(ParentWin, LPluginWin);
	SetWindowLongPtr(LPluginWin, GWLP_USERDATA, NativeInt(LWindow));

	LWindow.LoadFile(string(FileToLoad));
	LWindow.InitWebView2;

	Result := LPluginWin;
end;

function ListLoadNextW(ParentWin: HWND; ListWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): Integer; stdcall;
var
	LWindow: TGeminiListerWindow;
begin
	Result := LISTPLUGIN_ERROR;
	LWindow := TGeminiListerWindow(GetWindowLongPtr(ListWin, GWLP_USERDATA));
	if LWindow = nil then
		Exit;

	try
		LWindow.LoadFile(string(FileToLoad));
		Result := LISTPLUGIN_OK;
	except
		on E: Exception do
		begin
			Result := LISTPLUGIN_ERROR;
		end;
	end;
end;

function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;
var
	LWindow: TGeminiListerWindow;
	LScript: string;
	LCaseSensitive, LBackwards: Boolean;
begin
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
// Exported functions -- Thumbnails
// ========================================================================

const
	/// Buffer size for binary search through file content
	THUMB_SEARCH_BUF_SIZE = 65536;

	/// <summary>
	///   Performs a fast binary search for the first embedded image in a Gemini file.
	///   Locates the "inlineImage" marker, then extracts the base64 "data" field
	///   without full JSON parsing for speed.
	/// </summary>
function FindFirstImageBase64(const AFileName: string; out ABase64: TBytes): Boolean;
var
	LStream: TFileStream;
	LBuf: TBytes;
	LBytesRead, LOverlap, LPos, I: Integer;
	LFilePos: Int64;
	LMarker: RawByteString;
	LDataKey: RawByteString;
	LFound: Boolean;
	LByte: Byte;
	LRESULT: TBytesStream;
begin
	Result := False;
	LMarker := RawByteString('"inlineImage"');
	LDataKey := RawByteString('"data"');

	LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
	try
		LOverlap := Length(LMarker) - 1;
		SetLength(LBuf, THUMB_SEARCH_BUF_SIZE);
		LFilePos := 0;
		LFound := False;

		// Phase 1: find "inlineImage" marker using overlapping buffer reads
		while LFilePos < LStream.Size do
		begin
			LStream.Position := LFilePos;
			LBytesRead := LStream.Read(LBuf[0], THUMB_SEARCH_BUF_SIZE);
			if LBytesRead = 0 then
				Break;

			// Search for marker in current buffer
			for I := 0 to LBytesRead - Length(LMarker) do
			begin
				if CompareMem(@LBuf[I], @LMarker[1], Length(LMarker)) then
				begin
					// Position stream right after the marker
					LStream.Position := LFilePos + I + Length(LMarker);
					LFound := True;
					Break;
				end;
			end;

			if LFound then
				Break;

			// Advance with overlap to catch markers spanning buffer boundaries
			Inc(LFilePos, LBytesRead - LOverlap);
		end;

		if not LFound then
			Exit;

		// Phase 2: find "data" key after the marker (within the same inlineImage object)
		LFilePos := LStream.Position;
		LFound := False;

		while LFilePos < LStream.Size do
		begin
			LStream.Position := LFilePos;
			LBytesRead := LStream.Read(LBuf[0], THUMB_SEARCH_BUF_SIZE);
			if LBytesRead = 0 then
				Break;

			for I := 0 to LBytesRead - Length(LDataKey) do
			begin
				if CompareMem(@LBuf[I], @LDataKey[1], Length(LDataKey)) then
				begin
					LStream.Position := LFilePos + I + Length(LDataKey);
					LFound := True;
					Break;
				end;
			end;

			if LFound then
				Break;

			Inc(LFilePos, LBytesRead - (Length(LDataKey) - 1));
		end;

		if not LFound then
			Exit;

		// Phase 3: skip past `:` and whitespace to the opening `"` of the value
		while LStream.Position < LStream.Size do
		begin
			LStream.ReadBuffer(LByte, 1);
			if LByte = Ord('"') then
				Break;
		end;

		// Phase 4: read base64 content until closing `"`
		LRESULT := TBytesStream.Create;
		try
			SetLength(LBuf, THUMB_SEARCH_BUF_SIZE);
			while LStream.Position < LStream.Size do
			begin
				LBytesRead := LStream.Read(LBuf[0], THUMB_SEARCH_BUF_SIZE);
				if LBytesRead = 0 then
					Break;

				LPos := -1;
				for I := 0 to LBytesRead - 1 do
				begin
					if LBuf[I] = Ord('"') then
					begin
						LPos := I;
						Break;
					end;
				end;

				if LPos >= 0 then
				begin
					if LPos > 0 then
						LRESULT.WriteBuffer(LBuf[0], LPos);
					Break;
				end
				else
					LRESULT.WriteBuffer(LBuf[0], LBytesRead);
			end;

			if LRESULT.Size > 0 then
			begin
				ABase64 := Copy(LRESULT.Bytes, 0, LRESULT.Size);
				Result := True;
			end;
		finally
			LRESULT.Free;
		end;
	finally
		LStream.Free;
	end;
end;

/// <summary>
///   Decodes raw image bytes and creates a scaled HBITMAP thumbnail using WIC.
///   Returns 0 on any failure. Caller owns the returned HBITMAP.
/// </summary>
function ImageBytesToThumbnail(const AImageData: TBytes; AMaxWidth, AMaxHeight: Integer): HBITMAP;
var
	LFactory: IWICImagingFactory;
	LStream: TBytesStream;
	LAdapter: TStreamAdapter;
	LDecoder: IWICBitmapDecoder;
	LFrame: IWICBitmapFrameDecode;
	LScaler: IWICBitmapScaler;
	LConverter: IWICFormatConverter;
	LOrigW, LOrigH, LNewW, LNewH: UINT;
	LScale: Double;
	LBitmapInfo: TBitmapInfo;
	LBits: Pointer;
	LStride: UINT;
	LHr: HResult;
begin
	Result := 0;

	LHr := CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER, IWICImagingFactory, LFactory);
	if Failed(LHr) then
		Exit;

	LStream := TBytesStream.Create(AImageData);
	try
		LAdapter := TStreamAdapter.Create(LStream, soReference);

		LHr := LFactory.CreateDecoderFromStream(LAdapter, GUID_NULL, WICDecodeMetadataCacheOnDemand, LDecoder);
		if Failed(LHr) then
			Exit;

		LHr := LDecoder.GetFrame(0, LFrame);
		if Failed(LHr) then
			Exit;

		LHr := LFrame.GetSize(LOrigW, LOrigH);
		if Failed(LHr) or (LOrigW = 0) or (LOrigH = 0) then
			Exit;

		// Calculate scaled dimensions preserving aspect ratio
		LScale := Min(AMaxWidth / LOrigW, AMaxHeight / LOrigH);
		if LScale > 1.0 then
			LScale := 1.0; // Don't upscale
		LNewW := Round(LOrigW * LScale);
		LNewH := Round(LOrigH * LScale);
		if (LNewW = 0) or (LNewH = 0) then
			Exit;

		// Scale
		LHr := LFactory.CreateBitmapScaler(LScaler);
		if Failed(LHr) then
			Exit;

		LHr := LScaler.Initialize(LFrame, LNewW, LNewH, WICBitmapInterpolationModeFant);
		if Failed(LHr) then
			Exit;

		// Convert to 32bpp BGRA for CreateDIBSection compatibility
		LHr := LFactory.CreateFormatConverter(LConverter);
		if Failed(LHr) then
			Exit;

		LHr := LConverter.Initialize(LScaler, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nil, 0.0, WICBitmapPaletteTypeCustom);
		if Failed(LHr) then
			Exit;

		// Create top-down 32bpp DIB section
		FillChar(LBitmapInfo, SizeOf(LBitmapInfo), 0);
		LBitmapInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
		LBitmapInfo.bmiHeader.biWidth := LNewW;
		LBitmapInfo.bmiHeader.biHeight := -Integer(LNewH); // Top-down
		LBitmapInfo.bmiHeader.biPlanes := 1;
		LBitmapInfo.bmiHeader.biBitCount := 32;
		LBitmapInfo.bmiHeader.biCompression := BI_RGB;

		Result := CreateDIBSection(0, LBitmapInfo, DIB_RGB_COLORS, LBits, 0, 0);
		if Result = 0 then
			Exit;

		// Copy decoded pixels into the DIB
		LStride := LNewW * 4;
		LHr := LConverter.CopyPixels(nil, LStride, LStride * LNewH, LBits);
		if Failed(LHr) then
		begin
			DeleteObject(Result);
			Result := 0;
		end;
	finally
		LStream.Free;
	end;
end;

function ListGetPreviewBitmapW(FileToLoad: PWideChar; width, height: Integer; contentbuf: PAnsiChar; contentbuflen: Integer): HBITMAP; stdcall;
var
	LBase64Bytes, LImageData: TBytes;
begin
	Result := 0;
	try
		EnsureComInitialized;

		if not FindFirstImageBase64(string(FileToLoad), LBase64Bytes) then
			Exit;

		LImageData := TNetEncoding.Base64.Decode(LBase64Bytes);
		if Length(LImageData) = 0 then
			Exit;

		Result := ImageBytesToThumbnail(LImageData, width, height);
	except
		Result := 0;
	end;
end;

function ListGetPreviewBitmap(FileToLoad: PAnsiChar; width, height: Integer; contentbuf: PAnsiChar; contentbuflen: Integer): HBITMAP; stdcall;
var
	LWide: WideString;
begin
	LWide := WideString(AnsiString(FileToLoad));
	Result := ListGetPreviewBitmapW(PWideChar(LWide), width, height, contentbuf, contentbuflen);
end;

// ========================================================================
// Exported functions -- Common
// ========================================================================

procedure ListCloseWindow(ListWin: HWND); stdcall;
var
	LWindow: TGeminiListerWindow;
begin
	LWindow := TGeminiListerWindow(GetWindowLongPtr(ListWin, GWLP_USERDATA));
	SetWindowLongPtr(ListWin, GWLP_USERDATA, 0);
	if LWindow <> nil then
		LWindow.Free;
	DestroyWindow(ListWin);
end;

procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
const
	DETECT = 'FINDI("runSettings") & FINDI("models/gemini")';
begin
	System.AnsiStrings.StrLCopy(DetectString, PAnsiChar(AnsiString(DETECT)), MaxLen - 1);
end;

procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
begin
	// Required by TC but no configuration needed at this time
end;

function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
var
	LWindow: TGeminiListerWindow;
begin
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

finalization

// Intentionally NOT calling FreeLibrary(GLoaderHandle) here:
// finalization runs under DLL_PROCESS_DETACH (loader lock held),
// and FreeLibrary is unsafe under the loader lock per MSDN.
// The OS will unmap the DLL when the process exits.
GLoaderHandle := 0;
GCreateEnvironment := nil;

end.
