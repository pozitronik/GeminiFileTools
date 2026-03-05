/// <summary>
///   Shared utility functions for WCX and WLX plugins.
///   Consolidates plugin directory resolution, custom CSS loading,
///   HTML formatter configuration building, and shared INI defaults reading.
/// </summary>
unit GeminiPlugin.Shared;

interface

uses
	System.IniFiles,
	GeminiFile.Formatter.Html;

type
	/// <summary>
	///   Shared HTML rendering defaults read from [HtmlDefaults] INI section.
	///   Both WCX and WLX plugins use these same keys with the same semantics.
	/// </summary>
	TSharedHtmlDefaults = record
		DefaultFullWidth: Boolean;
		DefaultExpandThinking: Boolean;
		RenderMarkdown: Boolean;
		CollapseSystemInstruction: Boolean;
	end;

/// <summary>
///   Returns the directory containing the plugin DLL (via HInstance).
///   Returns empty string if GetModuleFileName fails.
/// </summary>
function GetPluginDir: string;

/// <summary>
///   Returns custom CSS content from gemini.css located next to the plugin DLL.
///   Result is cached on first call; returns empty string if file not found.
/// </summary>
function LoadCustomCSS: string;

/// <summary>
///   Builds a TGeminiHtmlFormatterConfig from individual parameters.
///   Centralises the mapping between plugin config fields and formatter config.
/// </summary>
function BuildHtmlFormatterConfig(
	AEmbedResources: Boolean;
	const ASourceFileName, ACustomCSS: string;
	AHideEmptyBlocks, ACombineBlocks: Boolean;
	const ADefaults: TSharedHtmlDefaults): TGeminiHtmlFormatterConfig;

/// <summary>
///   Reads the 4 shared HTML default fields from the [HtmlDefaults] INI section.
///   Plugin-specific fields remain in each plugin's own config reader.
/// </summary>
procedure ReadHtmlDefaults(AIni: TIniFile;
	ADefDefaultFullWidth, ADefDefaultExpandThinking,
	ADefRenderMarkdown, ADefCollapseSystemInstruction: Boolean;
	out ADefaults: TSharedHtmlDefaults);

implementation

uses
	Winapi.Windows,
	System.SysUtils,
	System.IOUtils;

var
	GCustomCSS: string;
	GCustomCSSLoaded: Boolean;

function GetPluginDir: string;
var
	LDllPath: array [0 .. MAX_PATH] of Char;
begin
	if GetModuleFileName(HInstance, LDllPath, MAX_PATH + 1) > 0 then
		Result := TPath.GetDirectoryName(LDllPath)
	else
		Result := '';
end;

function LoadCustomCSS: string;
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

function BuildHtmlFormatterConfig(
	AEmbedResources: Boolean;
	const ASourceFileName, ACustomCSS: string;
	AHideEmptyBlocks, ACombineBlocks: Boolean;
	const ADefaults: TSharedHtmlDefaults): TGeminiHtmlFormatterConfig;
begin
	Result := TGeminiHtmlFormatterConfig.Default;
	Result.EmbedResources := AEmbedResources;
	Result.SourceFileName := ASourceFileName;
	Result.CustomCSS := ACustomCSS;
	Result.HideEmptyBlocks := AHideEmptyBlocks;
	Result.CombineBlocks := ACombineBlocks;
	Result.DefaultFullWidth := ADefaults.DefaultFullWidth;
	Result.DefaultExpandThinking := ADefaults.DefaultExpandThinking;
	Result.RenderMarkdown := ADefaults.RenderMarkdown;
	Result.CollapseSystemInstruction := ADefaults.CollapseSystemInstruction;
end;

procedure ReadHtmlDefaults(AIni: TIniFile;
	ADefDefaultFullWidth, ADefDefaultExpandThinking,
	ADefRenderMarkdown, ADefCollapseSystemInstruction: Boolean;
	out ADefaults: TSharedHtmlDefaults);
begin
	ADefaults.DefaultFullWidth := AIni.ReadBool('HtmlDefaults', 'DefaultFullWidth', ADefDefaultFullWidth);
	ADefaults.DefaultExpandThinking := AIni.ReadBool('HtmlDefaults', 'DefaultExpandThinking', ADefDefaultExpandThinking);
	ADefaults.RenderMarkdown := AIni.ReadBool('HtmlDefaults', 'RenderMarkdown', ADefRenderMarkdown);
	ADefaults.CollapseSystemInstruction := AIni.ReadBool('HtmlDefaults', 'CollapseSystemInstruction', ADefCollapseSystemInstruction);
end;

end.
