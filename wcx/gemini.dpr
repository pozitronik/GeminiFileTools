/// <summary>
///   WCX plugin DLL for Total Commander.
///   Exposes Gemini conversation files as virtual archives.
///   Output: gemini.wcx (Win32) / gemini.wcx64 (Win64)
/// </summary>
library gemini;

{$IFDEF WIN64}
{$E wcx64}
{$ENDIF}
{$IFDEF WIN32}
{$E wcx}
{$ENDIF}

uses
	WcxApi in 'WcxApi.pas',
	GeminiWcx in 'GeminiWcx.pas',
	GeminiFile.Types in '..\src\GeminiFile.Types.pas',
	GeminiFile.Model in '..\src\GeminiFile.Model.pas',
	GeminiFile.Parser in '..\src\GeminiFile.Parser.pas',
	GeminiFile.Extractor in '..\src\GeminiFile.Extractor.pas',
	GeminiFile in '..\src\GeminiFile.pas',
	GeminiFile.Formatter.Text in '..\src\GeminiFile.Formatter.Text.pas',
	GeminiFile.Formatter.Md in '..\src\GeminiFile.Formatter.Md.pas',
	GeminiFile.Formatter.Html in '..\src\GeminiFile.Formatter.Html.pas',
	GeminiFile.Markdown in '..\src\GeminiFile.Markdown.pas';

exports
	// Unicode (primary)
	OpenArchiveW,
	ReadHeaderExW,
	ProcessFileW,
	CloseArchive,
	SetChangeVolProcW,
	SetProcessDataProcW,
	GetPackerCaps,
	CanYouHandleThisFileW,
	GetBackgroundFlags,
	// ANSI (compatibility)
	OpenArchive,
	ReadHeader,
	ReadHeaderEx,
	ProcessFile,
	SetChangeVolProc,
	SetProcessDataProc,
	CanYouHandleThisFile;

begin
end.
