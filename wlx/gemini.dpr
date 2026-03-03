/// <summary>
///   WLX lister plugin DLL for Total Commander.
///   Renders Gemini conversation files as HTML in an embedded WebView2 control.
///   Output: gemini.wlx (Win32) / gemini.wlx64 (Win64)
/// </summary>
library gemini;

{$IFDEF WIN64}
{$E wlx64}
{$ENDIF}
{$IFDEF WIN32}
{$E wlx}
{$ENDIF}

uses
	WlxApi in 'WlxApi.pas',
	GeminiWlx in 'GeminiWlx.pas',
	GeminiFile.Types in '..\src\GeminiFile.Types.pas',
	GeminiFile.Model in '..\src\GeminiFile.Model.pas',
	GeminiFile.Parser in '..\src\GeminiFile.Parser.pas',
	GeminiFile.Extractor in '..\src\GeminiFile.Extractor.pas',
	GeminiFile.LazyData in '..\src\GeminiFile.LazyData.pas',
	GeminiFile in '..\src\GeminiFile.pas',
	GeminiFile.Formatter.Intf in '..\src\GeminiFile.Formatter.Intf.pas',
	GeminiFile.Formatter.Utils in '..\src\GeminiFile.Formatter.Utils.pas',
	GeminiFile.Formatter.Base in '..\src\GeminiFile.Formatter.Base.pas',
	GeminiFile.Formatter.Html in '..\src\GeminiFile.Formatter.Html.pas',
	GeminiFile.Markdown in '..\src\GeminiFile.Markdown.pas',
	GeminiFile.Grouping in '..\src\GeminiFile.Grouping.pas';

exports
	// Unicode (primary)
	ListLoadW,
	ListLoadNextW,
	ListSearchTextW,
	// ANSI (compatibility)
	ListLoad,
	ListLoadNext,
	ListSearchText,
	// Common
	ListCloseWindow,
	ListGetDetectString,
	ListSetDefaultParams,
	ListSendCommand;

begin
end.
