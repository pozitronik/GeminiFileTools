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
	GeminiFile.Formatter.Html,
	GeminiPlugin.Shared;

const
	/// Thinking-block visibility modes stored in DefaultExpandThinking.
	/// Values 0 and 1 match the legacy boolean semantics for backward compatibility.
	THINKING_COLLAPSE = 0;
	THINKING_EXPAND = 1;
	THINKING_HIDE = 2;

type
	TListerConfig = record
		HideEmptyBlocks: Boolean;
		CombineBlocks: Boolean;
		RenderMarkdown: Boolean;
		DefaultFullWidth: Boolean;
		/// Thinking visibility: 0=collapse, 1=expand, 2=hide. Persisted across sessions.
		DefaultExpandThinking: Integer;
		CollapseSystemInstruction: Boolean;
		UserDataFolder: string;
		AllowContextMenu: Boolean;
		AllowDevTools: Boolean;
		ThumbnailFallback: string;
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

	/// <summary>
	///   Receives string messages posted from page JS via window.chrome.webview.postMessage.
	///   Used to persist UI state (thinking mode) back to gemini.ini.
	/// </summary>
	TWebMessageReceivedHandler = class(TInterfacedObject, ICoreWebView2WebMessageReceivedEventHandler)
	public
		function Invoke(const sender: ICoreWebView2; const args: ICoreWebView2WebMessageReceivedEventArgs): HResult; stdcall;
	end;

	/// <summary>
	///   Records a conversation role marker found during binary file scan.
	///   Used by the stripe thumbnail strategy to visualize conversation structure.
	/// </summary>
	TRoleMarker = record
		Role: Byte; // 0 = user, 1 = model
		ByteOffset: Int64; // position in file
	end;

function GetListerConfig: TListerConfig;

// --- Thumbnail helpers (public for testability) ---

/// <summary>
///   Scans a stream for a byte marker using overlapping buffer reads.
///   Returns byte offset of the first occurrence at or after AStartPos,
///   or -1 if not found. On success, AStream.Position is right after the marker.
/// </summary>
function FindByteMarker(AStream: TStream; const AMarker: RawByteString; AStartPos: Int64 = 0): Int64;

/// <summary>
///   Binary scan for "role" markers in a Gemini file.
///   For each marker, reads ahead past : and " to determine user vs model.
///   Returns array of role markers with byte offsets. No JSON parsing.
///   Also returns the file size to avoid a redundant file open by the caller.
/// </summary>
function ScanRoleMarkers(const AFileName: string; out AFileSize: Int64): TArray<TRoleMarker>;

/// <summary>
///   Extracts the first user message text via binary scan.
///   Finds first "role" with value starting with 'u', then searches backward
///   for "text" (which precedes "role" in chunk objects), reads the JSON string value.
///   Decodes JSON escapes and converts UTF-8 to string.
/// </summary>
function ExtractFirstUserText(const AFileName: string; AMaxChars: Integer = 200): string;

/// <summary>
///   Fast binary search for the first embedded image in a Gemini file.
///   Locates "inlineImage" marker, extracts the base64 "data" field.
///   No JSON parsing. Returns True if base64 data was found.
/// </summary>
function FindFirstImageBase64(const AFileName: string; out ABase64: TBytes): Boolean;

/// <summary>
///   Renders a stripe thumbnail showing conversation structure as horizontal bars.
///   Returns 0 if file has no role markers.
/// </summary>
function RenderStripeThumbnail(const AFileName: string; AWidth, AHeight: Integer): HBITMAP;

/// <summary>
///   Renders a text excerpt thumbnail with "User:" label and first user message.
///   Returns 0 if no user text found.
/// </summary>
function RenderTextExcerptThumbnail(const AFileName: string; AWidth, AHeight: Integer): HBITMAP;

/// <summary>
///   Renders a metadata badge thumbnail with model name and statistics.
///   Uses full JSON parsing. Returns 0 on failure.
/// </summary>
function RenderMetadataThumbnail(const AFileName: string; AWidth, AHeight: Integer): HBITMAP;

// --- Exported WLX functions ---

// Unicode (primary)
/// <summary>
///   Escapes a string for safe embedding in a JavaScript double-quoted string literal.
///   Handles backslashes, quotes, newlines, tabs, and Unicode line terminators.
/// </summary>
function JsEscapeString(const AStr: string): string;

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
	System.Types,
	System.NetEncoding,
	System.Generics.Collections,
	Winapi.Wincodec,
	GeminiFile.Formatter.Utils;

const
	GEMINI_LISTER_CLASS = 'GeminiListerClass';

	/// Default plugin configuration values
	DEF_HideEmptyBlocks = True;
	DEF_CombineBlocks = False;
	DEF_RenderMarkdown = True;
	DEF_DefaultFullWidth = False;
	DEF_DefaultExpandThinking = THINKING_COLLAPSE;
	DEF_CollapseSystemInstruction = True;
	DEF_AllowContextMenu = True;
	DEF_AllowDevTools = False;
	DEF_ThumbnailFallback = 'text';

	/// Thumbnail fallback strategy identifiers
	THUMB_FALLBACK_NONE = 'none';
	THUMB_FALLBACK_STRIPE = 'stripe';
	THUMB_FALLBACK_TEXT = 'text';
	THUMB_FALLBACK_METADATA = 'metadata';

	/// <summary>
	///   WLX-only client-side script appended to generated HTML.
	///   Replaces the formatter's two static thinking buttons with a single
	///   cycling button (Collapse -> Hide -> Expand) and posts mode changes
	///   back to the host via window.chrome.webview.postMessage for persistence.
	/// </summary>
	WLX_CONTROL_JS =
		'(function(){' +
		'var s=window.__geminiState||{thinkingMode:0};' +
		'function post(m){try{window.chrome.webview.postMessage(m);}catch(e){}}' +
		'function labelFor(m){return m===0?''Hide thinking'':m===2?''Expand thinking'':''Collapse thinking'';}' +
		'function nextMode(m){return m===0?2:m===2?1:0;}' +
		'function apply(m){' +
		'var h=(m===2);' +
		'document.body.classList.toggle(''thinking-hidden'',h);' +
		'if(!h){var ds=document.querySelectorAll(''details.thinking'');for(var i=0;i<ds.length;i++)ds[i].open=(m===1);}' +
		's.thinkingMode=m;' +
		'}' +
		'function init(){' +
		'var st=document.createElement(''style'');' +
		'st.textContent=''body.thinking-hidden details.thinking{display:none;}'';' +
		'document.head.appendChild(st);' +
		'apply(s.thinkingMode);' +
		'var c=document.getElementById(''controls'');if(!c)return;' +
		'var btns=c.querySelectorAll(''button'');var wb=null;' +
		'for(var i=0;i<btns.length;i++){var t=(btns[i].textContent||'''').trim();' +
		'if(t===''Expand thinking''||t===''Collapse thinking'')btns[i].remove();' +
		'else if(t===''Full width''||t===''Column width'')wb=btns[i];}' +
		// The formatter emits width toggle as an inline onclick which updates body class
		// and button label synchronously. Our listener runs after the inline handler
		// and observes the final state, so we simply report it back to the host.
		'if(wb)wb.addEventListener(''click'',function(){post(''fullWidth=''+(document.body.classList.contains(''full-width'')?''1'':''0''));});' +
		'var tb=document.createElement(''button'');tb.textContent=labelFor(s.thinkingMode);' +
		'tb.onclick=function(){var n=nextMode(s.thinkingMode);apply(n);tb.textContent=labelFor(n);post(''thinkingMode=''+n);};' +
		'c.appendChild(tb);' +
		'}' +
		'if(document.readyState===''loading'')document.addEventListener(''DOMContentLoaded'',init);else init();' +
		'})();';

type
	/// <summary>
	///   Function signature for CreateCoreWebView2EnvironmentWithOptions
	///   exported by WebView2Loader.dll.
	/// </summary>
	TCreateCoreWebView2EnvironmentWithOptionsFunc = function(browserExecutableFolder: LPCWSTR; UserDataFolder: LPCWSTR; const environmentOptions: ICoreWebView2EnvironmentOptions; const environmentCreatedHandler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HResult; stdcall;

var
	GClassRegistered: Boolean;
	GListerConfig: TListerConfig;
	GListerConfigLoaded: Boolean;
	GLoaderHandle: HMODULE;
	GCreateEnvironment: TCreateCoreWebView2EnvironmentWithOptionsFunc;
	GComInitialized: Boolean;

function GetListerConfig: TListerConfig;
var
	LIniPath: string;
	LIni: TIniFile;
	LHtmlDefaults: TSharedHtmlDefaults;
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
		GListerConfig.CollapseSystemInstruction := DEF_CollapseSystemInstruction;
		GListerConfig.AllowContextMenu := DEF_AllowContextMenu;
		GListerConfig.AllowDevTools := DEF_AllowDevTools;
		GListerConfig.ThumbnailFallback := DEF_ThumbnailFallback;

		LIniPath := TPath.Combine(GetPluginDir, 'gemini.ini');
		if TFile.Exists(LIniPath) then
		begin
			LIni := TIniFile.Create(LIniPath);
			try
				GListerConfig.HideEmptyBlocks := LIni.ReadBool('General', 'HideEmptyBlocks', DEF_HideEmptyBlocks);
				GListerConfig.CombineBlocks := LIni.ReadBool('General', 'CombineBlocks', DEF_CombineBlocks);
				GListerConfig.RenderMarkdown := LIni.ReadBool('General', 'RenderMarkdown', DEF_RenderMarkdown);
				ReadHtmlDefaults(LIni, DEF_DefaultFullWidth, DEF_DefaultExpandThinking <> THINKING_COLLAPSE,
					DEF_RenderMarkdown, DEF_CollapseSystemInstruction, LHtmlDefaults);
				GListerConfig.DefaultFullWidth := LHtmlDefaults.DefaultFullWidth;
				// Read DefaultExpandThinking as Integer (0=collapse, 1=expand, 2=hide).
				// Legacy boolean values 0/1 map cleanly; value 2 adds the "hide" state.
				GListerConfig.DefaultExpandThinking := LIni.ReadInteger('HtmlDefaults',
					'DefaultExpandThinking', DEF_DefaultExpandThinking);
				GListerConfig.CollapseSystemInstruction := LHtmlDefaults.CollapseSystemInstruction;
				// RenderMarkdown: prefer [General] value if set, fall back to [HtmlDefaults]
				// (WLX reads RenderMarkdown from General section, not HtmlDefaults)
				GListerConfig.UserDataFolder := LIni.ReadString('WebView2', 'UserDataFolder', '');
				GListerConfig.AllowContextMenu := LIni.ReadBool('WebView2', 'AllowContextMenu', DEF_AllowContextMenu);
				GListerConfig.AllowDevTools := LIni.ReadBool('WebView2', 'AllowDevTools', DEF_AllowDevTools);
				GListerConfig.ThumbnailFallback := LowerCase(LIni.ReadString('Thumbnails', 'Fallback', DEF_ThumbnailFallback));
			finally
				LIni.Free;
			end;
		end;
	end;
	Result := GListerConfig;
end;

/// <summary>Builds an HTML formatter config from WLX lister config.</summary>
function BuildWlxHtmlConfig(const AConfig: TListerConfig; AEmbedResources: Boolean;
	const ASourceFileName: string): TGeminiHtmlFormatterConfig;
var
	LDefaults: TSharedHtmlDefaults;
begin
	LDefaults.DefaultFullWidth := AConfig.DefaultFullWidth;
	// Formatter renders thinking blocks open only for the "expand" mode.
	// For "hide" mode, JS overlays display:none regardless of the open attribute.
	LDefaults.DefaultExpandThinking := AConfig.DefaultExpandThinking = THINKING_EXPAND;
	LDefaults.RenderMarkdown := AConfig.RenderMarkdown;
	LDefaults.CollapseSystemInstruction := AConfig.CollapseSystemInstruction;
	Result := BuildHtmlFormatterConfig(AEmbedResources, ASourceFileName, LoadCustomCSS,
		AConfig.HideEmptyBlocks, AConfig.CombineBlocks, LDefaults);
end;

/// <summary>
///   Persists the mutable parts of the lister config back to gemini.ini.
///   Silently ignores write failures (plugin dir may be read-only).
/// </summary>
procedure SaveListerConfig;
var
	LIniPath: string;
	LIni: TIniFile;
begin
	LIniPath := TPath.Combine(GetPluginDir, 'gemini.ini');
	try
		LIni := TIniFile.Create(LIniPath);
		try
			LIni.WriteInteger('HtmlDefaults', 'DefaultExpandThinking',
				GListerConfig.DefaultExpandThinking);
			LIni.WriteBool('HtmlDefaults', 'DefaultFullWidth',
				GListerConfig.DefaultFullWidth);
		finally
			LIni.Free;
		end;
	except
		// Ignore: plugin dir may be read-only (e.g., installed to Program Files)
	end;
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

/// <summary>
///   Appends the WLX-only initial state + controls script to a generated HTML stream.
///   Emits two script tags: one seeding window.__geminiState with the saved mode,
///   and one containing the WLX_CONTROL_JS body.
/// </summary>
procedure AppendWlxControlScript(AStream: TStream; AThinkingMode: Integer);
var
	LPayload: string;
	LBytes: TBytes;
begin
	LPayload :=
		sLineBreak + '<script>window.__geminiState={thinkingMode:' + IntToStr(AThinkingMode) + '};</script>' +
		sLineBreak + '<script>' + WLX_CONTROL_JS + '</script>' + sLineBreak;
	LBytes := TEncoding.UTF8.GetBytes(LPayload);
	if Length(LBytes) = 0 then
		Exit;
	AStream.Seek(0, soEnd);
	AStream.WriteBuffer(LBytes[0], Length(LBytes));
end;

function TGeminiListerWindow.GenerateHtml(const AFileName: string): string;
var
	LGeminiFile: TGeminiFile;
	LResources: TArray<TGeminiResource>;
	LResourceInfos: TArray<TFormatterResourceInfo>;
	LFmt: IGeminiFormatter;
	LStream: TMemoryStream;
	LConfig: TListerConfig;
	LHtmlConfig: TGeminiHtmlFormatterConfig;
	LTempPath: string;
	I: Integer;
begin
	Result := '';
	LConfig := GetListerConfig;

	LGeminiFile := TGeminiFile.Create;
	try
		LGeminiFile.LoadFromFile(AFileName);

		LResources := LGeminiFile.GetResources;
		LResourceInfos := BuildFormatterResourceInfos(LResources, LGeminiFile.Chunks);

		// Populate base64 data for embedded mode
		for I := 0 to High(LResources) do
			LResourceInfos[I].Base64Data := LResources[I].Base64Data;

		// Generate embedded HTML using shared config builder
		LHtmlConfig := BuildWlxHtmlConfig(LConfig, True,
			TPath.GetFileNameWithoutExtension(AFileName));
		LFmt := TGeminiHtmlFormatter.Create(LHtmlConfig);

		LStream := TMemoryStream.Create;
		try
			LFmt.FormatToStream(LStream, LGeminiFile.Chunks, LGeminiFile.SystemInstruction, LGeminiFile.RunSettings, LResourceInfos);

			// Append WLX-only script carrying saved thinking-mode state and control logic.
			// Appending after </html> is tolerated by all browsers and keeps the shared
			// formatter untouched. Avoids the cost of re-reading the stream for a replace.
			AppendWlxControlScript(LStream, LConfig.DefaultExpandThinking);

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

	// Receive postMessage calls from the page JS to persist UI state
	var
		LMsgToken: EventRegistrationToken;
	FOwner.FWebView.add_WebMessageReceived(TWebMessageReceivedHandler.Create, LMsgToken);

	// Size the WebView2 to fill the plugin window
	GetClientRect(FOwner.FPluginWin, Winapi.Windows.TRect(LRect));
	createdController.Set_Bounds(LRect);
	createdController.Set_IsVisible(1);
	createdController.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);

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

	if Failed(args.Get_VirtualKey(LKey)) then
		Exit;

	// Navigation keys go to WebView2 (with or without Shift for text selection)
	case LKey of
		VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_PRIOR, VK_NEXT, VK_HOME, VK_END, VK_SPACE, VK_BACK:
			Exit;
	end;

	// Ctrl+clipboard shortcuts go to WebView2
	if GetKeyState(VK_CONTROL) < 0 then
		case LKey of
			Ord('C'), Ord('A'), Ord('V'), Ord('X'):
				Exit;
		end;

	// Forward non-character keys to TC (Esc, F-keys, modifier combos).
	// Note: character keys (letters, numbers, Tab) bypass AcceleratorKeyPressed
	// entirely and are consumed by WebView2 — this is a WebView2 limitation.
	args.Set_Handled(1);
	PostMessage(FParentWin, WM_KEYDOWN, LKey, 0);
end;

// ========================================================================
// TWebMessageReceivedHandler
// ========================================================================

function TWebMessageReceivedHandler.Invoke(const sender: ICoreWebView2;
	const args: ICoreWebView2WebMessageReceivedEventArgs): HResult; stdcall;
var
	LPtr: PWideChar;
	LMsg, LKey, LVal: string;
	LEqPos: Integer;
begin
	Result := S_OK;
	if args = nil then
		Exit;
	if Failed(args.TryGetWebMessageAsString(LPtr)) or (LPtr = nil) then
		Exit;
	try
		LMsg := string(LPtr);
	finally
		CoTaskMemFree(LPtr);
	end;

	// Simple key=value protocol avoids pulling in a JSON parser for three tiny messages
	LEqPos := Pos('=', LMsg);
	if LEqPos <= 0 then
		Exit;
	LKey := Copy(LMsg, 1, LEqPos - 1);
	LVal := Copy(LMsg, LEqPos + 1, MaxInt);

	if LKey = 'thinkingMode' then
	begin
		GListerConfig.DefaultExpandThinking := StrToIntDef(LVal, THINKING_COLLAPSE);
		SaveListerConfig;
	end
	else if LKey = 'fullWidth' then
	begin
		GListerConfig.DefaultFullWidth := LVal = '1';
		SaveListerConfig;
	end;
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

function JsEscapeString(const AStr: string): string;
var
	LSB: TStringBuilder;
	I: Integer;
	LCh: Char;
begin
	if AStr = '' then
		Exit('');

	LSB := TStringBuilder.Create(Length(AStr) + Length(AStr) div 4);
	try
		for I := 1 to Length(AStr) do
		begin
			LCh := AStr[I];
			case LCh of
				'\': LSB.Append('\\');
				'"': LSB.Append('\"');
				#8:  LSB.Append('\b');
				#9:  LSB.Append('\t');
				#10: LSB.Append('\n');
				#12: LSB.Append('\f');
				#13: LSB.Append('\r');
				#$2028: LSB.Append('\u2028');
				#$2029: LSB.Append('\u2029');
			else
				LSB.Append(LCh);
			end;
		end;
		Result := LSB.ToString;
	finally
		LSB.Free;
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

	LScript := Format('window.find("%s", %s, %s, false, false, false, false)', [
		JsEscapeString(string(SearchString)),
		LowerCase(BoolToStr(LCaseSensitive, True)),
		LowerCase(BoolToStr(LBackwards, True))]);

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

function FindByteMarker(AStream: TStream; const AMarker: RawByteString; AStartPos: Int64): Int64;
var
	LBuf: TBytes;
	LBytesRead, LOverlap, I, LMarkerLen: Integer;
	LFilePos: Int64;
begin
	Result := -1;
	LMarkerLen := Length(AMarker);
	if (LMarkerLen = 0) or (AStartPos >= AStream.Size) then
		Exit;

	LOverlap := LMarkerLen - 1;
	SetLength(LBuf, THUMB_SEARCH_BUF_SIZE);
	LFilePos := AStartPos;

	while LFilePos < AStream.Size do
	begin
		AStream.Position := LFilePos;
		LBytesRead := AStream.Read(LBuf[0], THUMB_SEARCH_BUF_SIZE);
		if LBytesRead < LMarkerLen then
			Exit;

		for I := 0 to LBytesRead - LMarkerLen do
		begin
			if CompareMem(@LBuf[I], @AMarker[1], LMarkerLen) then
			begin
				AStream.Position := LFilePos + I + LMarkerLen;
				Result := LFilePos + I;
				Exit;
			end;
		end;

		Inc(LFilePos, LBytesRead - LOverlap);
	end;
end;

	/// <summary>
	///   Performs a fast binary search for the first embedded image in a Gemini file.
	///   Locates the "inlineImage" marker, then extracts the base64 "data" field
	///   without full JSON parsing for speed.
	/// </summary>
function FindFirstImageBase64(const AFileName: string; out ABase64: TBytes): Boolean;
var
	LStream: TFileStream;
	LBuf: TBytes;
	LBytesRead, LPos, I: Integer;
	LByte: Byte;
	LResult: TBytesStream;
begin
	Result := False;

	LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
	try
		// Phase 1: find "inlineImage" marker
		if FindByteMarker(LStream, '"inlineImage"') < 0 then
			Exit;

		// Phase 2: find "data" key after the marker
		if FindByteMarker(LStream, '"data"', LStream.Position) < 0 then
			Exit;

		// Phase 3: skip past `:` and whitespace to the opening `"` of the value
		while LStream.Position < LStream.Size do
		begin
			LStream.ReadBuffer(LByte, 1);
			if LByte = Ord('"') then
				Break;
		end;

		// Phase 4: read base64 content until closing `"`
		LResult := TBytesStream.Create;
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
						LResult.WriteBuffer(LBuf[0], LPos);
					Break;
				end
				else
					LResult.WriteBuffer(LBuf[0], LBytesRead);
			end;

			if LResult.Size > 0 then
			begin
				ABase64 := Copy(LResult.Bytes, 0, LResult.Size);
				Result := True;
			end;
		finally
			LResult.Free;
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

/// <summary>
///   Creates a top-down 32bpp DIB section and a memory DC with the bitmap selected.
///   Fills the entire bitmap with the specified background color.
///   Caller must call DeleteDC(ADC) and owns the returned HBITMAP.
/// </summary>
function CreateThumbnailDIB(AWidth, AHeight: Integer; ABgColor: COLORREF; out ADC: HDC): HBITMAP;
var
	LBitmapInfo: TBitmapInfo;
	LBits: Pointer;
	LBrush: HBRUSH;
	LRect: TRect;
begin
	ADC := 0;
	FillChar(LBitmapInfo, SizeOf(LBitmapInfo), 0);
	LBitmapInfo.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
	LBitmapInfo.bmiHeader.biWidth := AWidth;
	LBitmapInfo.bmiHeader.biHeight := -AHeight; // Top-down
	LBitmapInfo.bmiHeader.biPlanes := 1;
	LBitmapInfo.bmiHeader.biBitCount := 32;
	LBitmapInfo.bmiHeader.biCompression := BI_RGB;

	Result := CreateDIBSection(0, LBitmapInfo, DIB_RGB_COLORS, LBits, 0, 0);
	if Result = 0 then
		Exit;

	ADC := CreateCompatibleDC(0);
	if ADC = 0 then
	begin
		DeleteObject(Result);
		Result := 0;
		Exit;
	end;
	SelectObject(ADC, Result);

	// Fill background
	LRect := Rect(0, 0, AWidth, AHeight);
	LBrush := CreateSolidBrush(ABgColor);
	FillRect(ADC, LRect, LBrush);
	DeleteObject(LBrush);
end;

function ScanRoleMarkers(const AFileName: string; out AFileSize: Int64): TArray<TRoleMarker>;
var
	LStream: TFileStream;
	LByte: Byte;
	LMarkerList: TList<TRoleMarker>;
	LRoleMarker: TRoleMarker;
	LOffset: Int64;
	LSearchFrom: Int64;
begin
	Result := nil;
	AFileSize := 0;

	LMarkerList := TList<TRoleMarker>.Create;
	try
		LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
		try
			AFileSize := LStream.Size;
			LSearchFrom := 0;

			while True do
			begin
				LOffset := FindByteMarker(LStream, '"role"', LSearchFrom);
				if LOffset < 0 then
					Break;

				// Skip whitespace and colon to find opening quote
				while LStream.Position < LStream.Size do
				begin
					LStream.ReadBuffer(LByte, 1);
					if LByte = Ord('"') then
						Break;
				end;

				// Read first character of the role value
				if LStream.Position < LStream.Size then
				begin
					LStream.ReadBuffer(LByte, 1);
					LRoleMarker.ByteOffset := LOffset;
					if LByte = Ord('u') then
						LRoleMarker.Role := 0 // user
					else if LByte = Ord('m') then
						LRoleMarker.Role := 1 // model
					else
					begin
						LSearchFrom := LStream.Position;
						Continue; // unknown role, skip
					end;
					LMarkerList.Add(LRoleMarker);
				end;

				LSearchFrom := LStream.Position;
			end;
		finally
			LStream.Free;
		end;

		Result := LMarkerList.ToArray;
	finally
		LMarkerList.Free;
	end;
end;

/// <summary>
///   Renders a stripe thumbnail showing conversation structure as horizontal bars.
///   Each bar's height is proportional to the byte distance between consecutive role markers.
///   User = warm blue, Model = muted green. 1px separator on light gray background.
/// </summary>
function RenderStripeThumbnail(const AFileName: string; AWidth, AHeight: Integer): HBITMAP;
const
	COLOR_USER = $00BB7733; // warm blue (BGR)
	COLOR_MODEL = $0044AA55; // muted green (BGR)
	COLOR_BG = $00F0F0F0; // light gray
	COLOR_SEP = $00D0D0D0; // separator
var
	LMarkers: TArray<TRoleMarker>;
	LDC: HDC;
	LTotalBytes: Int64;
	LBrush: HBRUSH;
	LRect: TRect;
	I, LY, LBarH: Integer;
	LSegmentBytes: Int64;
	LFileSize: Int64;
begin
	Result := 0;
	LMarkers := ScanRoleMarkers(AFileName, LFileSize);
	if (Length(LMarkers) = 0) or (LFileSize = 0) then
		Exit;

	// Total conversation span: from first marker to end of file
	LTotalBytes := LFileSize - LMarkers[0].ByteOffset;
	if LTotalBytes <= 0 then
		Exit;

	Result := CreateThumbnailDIB(AWidth, AHeight, COLOR_BG, LDC);
	if Result = 0 then
		Exit;

	try
		LY := 0;
		for I := 0 to High(LMarkers) do
		begin
			// Segment size: distance to next marker, or to end of file for last marker
			if I < High(LMarkers) then
				LSegmentBytes := LMarkers[I + 1].ByteOffset - LMarkers[I].ByteOffset
			else
				LSegmentBytes := LFileSize - LMarkers[I].ByteOffset;

			LBarH := Round((LSegmentBytes / LTotalBytes) * AHeight);
			// Last segment fills remaining space to avoid rounding gaps
			if I = High(LMarkers) then
				LBarH := AHeight - LY;
			if LBarH <= 0 then
				LBarH := 1;

			// Draw the colored bar
			if LMarkers[I].Role = 0 then
				LBrush := CreateSolidBrush(COLOR_USER)
			else
				LBrush := CreateSolidBrush(COLOR_MODEL);
			LRect := Rect(0, LY, AWidth, LY + LBarH);
			FillRect(LDC, LRect, LBrush);
			DeleteObject(LBrush);

			// 1px separator between bars (except after the last one)
			if (I < High(LMarkers)) and (LBarH > 1) then
			begin
				LBrush := CreateSolidBrush(COLOR_SEP);
				LRect := Rect(0, LY + LBarH - 1, AWidth, LY + LBarH);
				FillRect(LDC, LRect, LBrush);
				DeleteObject(LBrush);
			end;

			Inc(LY, LBarH);
		end;
	finally
		DeleteDC(LDC);
	end;
end;

function ExtractFirstUserText(const AFileName: string; AMaxChars: Integer = 200): string;
var
	LStream: TFileStream;
	LBuf: TBytes;
	LBytesRead, I, LPos: Integer;
	LFilePos, LUserOffset: Int64;
	LTextKey: RawByteString;
	LByte: Byte;
	LFound: Boolean;
	LTextBytes: TBytesStream;
	LRawText: UTF8String;
	LRESULT: string;
	LHexBuf: array [0 .. 3] of Byte;
	LCodePoint: Integer;
	LUtf8: UTF8String;
	LSearchFrom: Int64;
begin
	Result := '';
	LTextKey := RawByteString('"text"');

	LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
	try
		// Phase 1: find first "role" with value starting with 'u'
		LSearchFrom := 0;
		while True do
		begin
			LUserOffset := FindByteMarker(LStream, '"role"', LSearchFrom);
			if LUserOffset < 0 then
				Exit;

			// Skip past : and " to get first char
			while LStream.Position < LStream.Size do
			begin
				LStream.ReadBuffer(LByte, 1);
				if LByte = Ord('"') then
					Break;
			end;
			if LStream.Position < LStream.Size then
			begin
				LStream.ReadBuffer(LByte, 1);
				if LByte = Ord('u') then
					Break; // found user role
			end;
			LSearchFrom := LStream.Position;
		end;

		// Phase 2: search backward from user "role" offset for "text" key
		// Search in the region before the role marker (up to 4KB back)
		SetLength(LBuf, THUMB_SEARCH_BUF_SIZE);
		LFilePos := Max(0, LUserOffset - 4096);
		LStream.Position := LFilePos;
		LBytesRead := LStream.Read(LBuf[0], Min(THUMB_SEARCH_BUF_SIZE, LUserOffset - LFilePos));
		if LBytesRead = 0 then
			Exit;

		// Find last occurrence of "text" before the role marker
		LFound := False;
		LPos := -1;
		for I := LBytesRead - Length(LTextKey) downto 0 do
		begin
			if CompareMem(@LBuf[I], @LTextKey[1], Length(LTextKey)) then
			begin
				LPos := I;
				LFound := True;
				Break;
			end;
		end;

		if not LFound then
			Exit;

		// Phase 3: skip past "text" : " to get to the value
		LStream.Position := LFilePos + LPos + Length(LTextKey);
		while LStream.Position < LStream.Size do
		begin
			LStream.ReadBuffer(LByte, 1);
			if LByte = Ord('"') then
				Break;
		end;

		// Phase 4: read JSON string value until closing unescaped quote
		LTextBytes := TBytesStream.Create;
		try
			while LStream.Position < LStream.Size do
			begin
				LStream.ReadBuffer(LByte, 1);
				if LByte = Ord('"') then
					Break;
				if LByte = Ord('\') then
				begin
					// JSON escape sequence
					if LStream.Position >= LStream.Size then
						Break;
					LStream.ReadBuffer(LByte, 1);
					case Chr(LByte) of
						'n':
							LByte := Ord(#10);
						'r':
							LByte := Ord(#13);
						't':
							LByte := Ord(#9);
						'b':
							LByte := Ord(#8);
						'f':
							LByte := Ord(#12);
						'\', '"', '/':
							; // LByte already holds the literal character
						'u':
							begin
								// \uXXXX Unicode escape
								if LStream.Position + 4 > LStream.Size then
									Break;
								LStream.ReadBuffer(LHexBuf[0], 4);
								LCodePoint := StrToIntDef('$' + Chr(LHexBuf[0]) + Chr(LHexBuf[1]) + Chr(LHexBuf[2]) + Chr(LHexBuf[3]), -1);
								if LCodePoint >= 0 then
								begin
									LUtf8 := UTF8Encode(WideString(WideChar(LCodePoint)));
									LTextBytes.WriteBuffer(LUtf8[1], Length(LUtf8));
								end;
								Continue; // already written, skip the WriteBuffer below
							end;
						else
							// Unknown escape -- preserve the escaped character only
					end;
				end;
				LTextBytes.WriteBuffer(LByte, 1);
				// Early termination: enough bytes for MaxChars (UTF-8 can be multi-byte)
				if LTextBytes.Size > AMaxChars * 4 then
					Break;
			end;

			if LTextBytes.Size = 0 then
				Exit;

			// Convert UTF-8 bytes to string
			SetLength(LRawText, LTextBytes.Size);
			Move(LTextBytes.Bytes[0], LRawText[1], LTextBytes.Size);
			LRESULT := UTF8ToString(LRawText);

			// Truncate to MaxChars
			if Length(LRESULT) > AMaxChars then
				LRESULT := Copy(LRESULT, 1, AMaxChars);

			Result := LRESULT;
		finally
			LTextBytes.Free;
		end;
	finally
		LStream.Free;
	end;
end;

/// <summary>
///   Renders a text excerpt thumbnail as a white card with a "User:" label
///   and the first user message text below it.
/// </summary>
function RenderTextExcerptThumbnail(const AFileName: string; AWidth, AHeight: Integer): HBITMAP;
const
	COLOR_BG = $00FFFFFF; // white
	COLOR_BORDER = $00C0C0C0; // light gray border
	COLOR_LABEL = $00888888; // gray label
	COLOR_TEXT = $00222222; // near-black text
var
	LText: string;
	LDC: HDC;
	LFont, LOldFont: HFONT;
	LPadding, LFontSize, LLabelH: Integer;
	LRect: TRect;
	LBrush, LPen: HGDIOBJ;
begin
	Result := 0;
	LText := ExtractFirstUserText(AFileName);
	if LText = '' then
		Exit;

	Result := CreateThumbnailDIB(AWidth, AHeight, COLOR_BG, LDC);
	if Result = 0 then
		Exit;

	try
		// Draw border
		LBrush := GetStockObject(NULL_BRUSH);
		SelectObject(LDC, LBrush);
		LPen := CreatePen(PS_SOLID, 1, COLOR_BORDER);
		SelectObject(LDC, LPen);
		Rectangle(LDC, 0, 0, AWidth, AHeight);
		DeleteObject(LPen);

		LPadding := AWidth div 16;
		if LPadding < 4 then
			LPadding := 4;
		LFontSize := AHeight div 12;
		if LFontSize < 10 then
			LFontSize := 10;

		SetBkMode(LDC, TRANSPARENT);

		// Draw "User:" label
		LFont := CreateFont(-LFontSize, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH or FF_SWISS, 'Segoe UI');
		LOldFont := SelectObject(LDC, LFont);
		SetTextColor(LDC, COLOR_LABEL);
		LRect := Rect(LPadding, LPadding, AWidth - LPadding, LPadding + LFontSize + 4);
		DrawTextW(LDC, 'User:', 5, LRect, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX);
		LLabelH := LRect.Bottom - LRect.Top;
		SelectObject(LDC, LOldFont);
		DeleteObject(LFont);

		// Draw excerpt text
		LFont := CreateFont(-LFontSize, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH or FF_SWISS, 'Segoe UI');
		LOldFont := SelectObject(LDC, LFont);
		SetTextColor(LDC, COLOR_TEXT);
		LRect := Rect(LPadding, LPadding + LLabelH + 2, AWidth - LPadding, AHeight - LPadding);
		DrawTextW(LDC, PChar(LText), Length(LText), LRect, DT_LEFT or DT_WORDBREAK or DT_END_ELLIPSIS or DT_NOPREFIX);
		SelectObject(LDC, LOldFont);
		DeleteObject(LFont);
	finally
		DeleteDC(LDC);
	end;
end;

/// <summary>
///   Renders a metadata badge thumbnail with model name and conversation statistics.
///   Uses full JSON parsing via TGeminiFile. Slowest strategy but shows rich info.
/// </summary>
function RenderMetadataThumbnail(const AFileName: string; AWidth, AHeight: Integer): HBITMAP;
const
	COLOR_BG = $00F8F8F8; // off-white
	COLOR_ACCENT = $00CC6600; // blue accent bar (BGR)
	COLOR_MODEL = $00333333; // dark text for model name
	COLOR_STATS = $00666666; // medium gray for stats
var
	LGeminiFile: TGeminiFile;
	LModelName, LChunkStr, LTokenStr: string;
	LTotalTokens, I: Integer;
	LDC: HDC;
	LFont, LOldFont: HFONT;
	LFontSize, LPadding, LAccentH, LY: Integer;
	LRect: TRect;
	LBrush: HBRUSH;
begin
	LGeminiFile := TGeminiFile.Create;
	try
		LGeminiFile.LoadFromFile(AFileName);

		// Extract model name, strip "models/" prefix
		LModelName := '';
		if LGeminiFile.RunSettings <> nil then
		begin
			LModelName := LGeminiFile.RunSettings.Model;
			if LModelName.StartsWith('models/') then
				LModelName := Copy(LModelName, 8, MaxInt);
		end;
		if LModelName = '' then
			LModelName := 'Unknown model';

		// Count chunks and total tokens
		LChunkStr := IntToStr(LGeminiFile.Chunks.Count) + ' chunks';

		LTotalTokens := 0;
		for I := 0 to LGeminiFile.Chunks.Count - 1 do
			Inc(LTotalTokens, LGeminiFile.Chunks[I].TokenCount);
		LTokenStr := FormatFloat('#,##0', LTotalTokens) + ' tokens';
	finally
		LGeminiFile.Free;
	end;

	Result := CreateThumbnailDIB(AWidth, AHeight, COLOR_BG, LDC);
	if Result = 0 then
		Exit;

	try
		LPadding := AWidth div 16;
		if LPadding < 4 then
			LPadding := 4;
		LAccentH := 3;

		// Blue accent bar at top
		LBrush := CreateSolidBrush(COLOR_ACCENT);
		LRect := Rect(0, 0, AWidth, LAccentH);
		FillRect(LDC, LRect, LBrush);
		DeleteObject(LBrush);

		SetBkMode(LDC, TRANSPARENT);
		LFontSize := AHeight div 10;
		if LFontSize < 10 then
			LFontSize := 10;

		// Model name -- centered, bold, larger
		LFont := CreateFont(-(LFontSize + 2), 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH or FF_SWISS, 'Segoe UI');
		LOldFont := SelectObject(LDC, LFont);
		SetTextColor(LDC, COLOR_MODEL);
		LY := LAccentH + LPadding + (AHeight - LAccentH) div 4 - LFontSize;
		LRect := Rect(LPadding, LY, AWidth - LPadding, LY + LFontSize + 6);
		DrawTextW(LDC, PChar(LModelName), Length(LModelName), LRect, DT_CENTER or DT_SINGLELINE or DT_END_ELLIPSIS or DT_NOPREFIX);
		SelectObject(LDC, LOldFont);
		DeleteObject(LFont);

		// Stats lines -- centered, normal, smaller
		LFont := CreateFont(-LFontSize, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH or FF_SWISS, 'Segoe UI');
		LOldFont := SelectObject(LDC, LFont);
		SetTextColor(LDC, COLOR_STATS);

		LY := LAccentH + (AHeight - LAccentH) div 2;
		LRect := Rect(LPadding, LY, AWidth - LPadding, LY + LFontSize + 4);
		DrawTextW(LDC, PChar(LChunkStr), Length(LChunkStr), LRect, DT_CENTER or DT_SINGLELINE or DT_NOPREFIX);

		Inc(LY, LFontSize + 6);
		LRect := Rect(LPadding, LY, AWidth - LPadding, LY + LFontSize + 4);
		DrawTextW(LDC, PChar(LTokenStr), Length(LTokenStr), LRect, DT_CENTER or DT_SINGLELINE or DT_NOPREFIX);

		SelectObject(LDC, LOldFont);
		DeleteObject(LFont);
	finally
		DeleteDC(LDC);
	end;
end;

function ListGetPreviewBitmapW(FileToLoad: PWideChar; width, height: Integer; contentbuf: PAnsiChar; contentbuflen: Integer): HBITMAP; stdcall;
var
	LBase64Bytes, LImageData: TBytes;
	LFileName: string;
	LFallback: string;
begin
	Result := 0;
	try
		EnsureComInitialized;
		LFileName := string(FileToLoad);

		// Primary path: embedded image thumbnail
		if FindFirstImageBase64(LFileName, LBase64Bytes) then
		begin
			LImageData := TNetEncoding.Base64.Decode(LBase64Bytes);
			if Length(LImageData) > 0 then
				Result := ImageBytesToThumbnail(LImageData, width, height);
			if Result <> 0 then
				Exit;
		end;

		// Fallback strategies for files without embedded images
		LFallback := GetListerConfig.ThumbnailFallback;
		if LFallback = THUMB_FALLBACK_STRIPE then
			Result := RenderStripeThumbnail(LFileName, width, height)
		else if LFallback = THUMB_FALLBACK_TEXT then
			Result := RenderTextExcerptThumbnail(LFileName, width, height)
		else if LFallback = THUMB_FALLBACK_METADATA then
			Result := RenderMetadataThumbnail(LFileName, width, height);
		// THUMB_FALLBACK_NONE or unknown: Result stays 0
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
	DETECT = 'FINDI("runSettings") & FINDI("models/")';
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
