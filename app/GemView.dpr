/// <summary>
///   GemView -- Console application for viewing and extracting data from
///   Gemini AI Studio files and Claude Console session exports.
///
///   Usage:
///     gemview sessions <file>       List sessions and saved versions
///     gemview export <file> [options]  Export HTML, Markdown or text
///     gemview info <file>           Show file metadata and statistics
///     gemview conversation <file>   Print the conversation text
///     gemview resources <file>      List embedded resources
///     gemview extract <file> [options]  Extract embedded resources to files
///     gemview help                  Show usage information
///
///   Extract options:
///     --output <dir>      Output directory (default: <filename>_resources)
///     --sequential        Use single-threaded extraction
///     --prefix <name>     Filename prefix (default: resource)
/// </summary>
program GemView;

{$APPTYPE CONSOLE}
{$R *.res}

uses
	Winapi.Windows,
	System.SysUtils,
	System.Classes,
	System.Math,
	System.IOUtils,
	GeminiFile.Types in '..\src\GeminiFile.Types.pas',
	GeminiFile.Model in '..\src\GeminiFile.Model.pas',
	GeminiFile.Parser in '..\src\GeminiFile.Parser.pas',
	GeminiFile.Extractor in '..\src\GeminiFile.Extractor.pas',
	GeminiFile.LazyData in '..\src\GeminiFile.LazyData.pas',
	ClaudeFile.Parser in '..\src\ClaudeFile.Parser.pas',
	ConversationFile in '..\src\ConversationFile.pas',
	GeminiFile.Formatter.Intf in '..\src\GeminiFile.Formatter.Intf.pas',
	GeminiFile.Formatter.Utils in '..\src\GeminiFile.Formatter.Utils.pas',
	GeminiFile.Formatter.Base in '..\src\GeminiFile.Formatter.Base.pas',
	GeminiFile.Formatter.Text in '..\src\GeminiFile.Formatter.Text.pas',
	GeminiFile.Formatter.Md in '..\src\GeminiFile.Formatter.Md.pas',
	GeminiFile.Formatter.Html in '..\src\GeminiFile.Formatter.Html.pas',
	GeminiFile.Markdown in '..\src\GeminiFile.Markdown.pas',
	GeminiFile.Grouping in '..\src\GeminiFile.Grouping.pas',
	ConversationFile.Formatter in '..\src\ConversationFile.Formatter.pas',
	GeminiFile in '..\src\GeminiFile.pas';

const
	APP_VERSION = '0.2.0';

type
	TCliOptions = record
		SessionIndex: Integer;
		VersionIndex: Integer;
		OutputPath: string;
		Prefix: string;
		Sequential: Boolean;
		ExportFormat: TConversationExportFormat;
		Images: TRemoteImageMode;
	end;

procedure PrintHelp;
begin
	WriteLn('GemView v', APP_VERSION, ' -- Gemini and Claude Console conversation viewer/extractor');
	WriteLn('Usage: gemview <command> <file> [options]');
	WriteLn('  sessions       List sessions and saved versions');
	WriteLn('  info           Show metadata, settings and statistics');
	WriteLn('  conversation   Print conversation text (latest version of every session)');
	WriteLn('  export         Export HTML, Markdown or text (default: HTML)');
	WriteLn('  resources      List embedded resources and remote image URLs');
	WriteLn('  extract        Extract embedded resources');
	WriteLn('Options:');
	WriteLn('  --session N    Select one session (1-based)');
	WriteLn('  --version N    Select a saved version (1-based; requires --session)');
	WriteLn('  --output PATH  Export file or extraction directory (otherwise stdout)');
	WriteLn('  --format FMT   html, md, txt');
	WriteLn('  --images MODE  links (default), fetch, load');
	WriteLn('  --sequential   Extract resources without worker threads');
	WriteLn('  --prefix NAME  Extracted resource prefix (default: resource)');
end;

function ReadOptions(const ACommand: string): TCliOptions;
var
	I, LIndex: Integer;
	LParam, LValue: string;
begin
	Result := Default(TCliOptions);
	Result.SessionIndex := -1;
	Result.VersionIndex := -1;
	Result.Prefix := 'resource';
	Result.ExportFormat := cefText;
	if ACommand = 'export' then
		Result.ExportFormat := cefHtml;
	I := 3;
	while I <= ParamCount do
	begin
		LParam := LowerCase(ParamStr(I));
		if LParam = '--sequential' then
			Result.Sequential := True
		else
		begin
			if I = ParamCount then
				raise EArgumentException.Create('Missing value for ' + LParam);
			Inc(I);
			LValue := ParamStr(I);
			if (LParam = '--session') or (LParam = '--version') then
			begin
				if not TryStrToInt(LValue, LIndex) or (LIndex < 1) then
					raise EArgumentException.Create(LParam + ' must be a positive integer');
				if LParam = '--session' then
					Result.SessionIndex := LIndex - 1
				else
					Result.VersionIndex := LIndex - 1;
			end
			else
				if LParam = '--output' then
				Result.OutputPath := LValue
			else
				if LParam = '--prefix' then
				Result.Prefix := LValue
			else
				if LParam = '--format' then
			begin
				if SameText(LValue, 'html') then
					Result.ExportFormat := cefHtml
				else if SameText(LValue, 'md') then
					Result.ExportFormat := cefMarkdown
				else if SameText(LValue, 'txt') then
					Result.ExportFormat := cefText
				else
					raise EArgumentException.Create('Format must be html, md or txt');
			end
			else
				if LParam = '--images' then
			begin
				if SameText(LValue, 'links') then
					Result.Images := rimLinks
				else if SameText(LValue, 'fetch') then
					Result.Images := rimFetch
				else if SameText(LValue, 'load') then
					Result.Images := rimLoad
				else
					raise EArgumentException.Create('Images mode must be links, fetch or load');
			end
			else
				raise EArgumentException.Create('Unknown option: ' + LParam);
		end;
		Inc(I);
	end;
	if (Result.VersionIndex >= 0) and (Result.SessionIndex < 0) then
		raise EArgumentException.Create('--version requires --session');
end;

procedure ValidateSelection(AFile: TConversationFile; const AOptions: TCliOptions);
begin
	if AOptions.SessionIndex >= AFile.Sessions.Count then
		raise EArgumentException.Create('Session index out of range');
	if (AOptions.VersionIndex >= 0) and
		(AOptions.VersionIndex >= AFile.Sessions[AOptions.SessionIndex].Versions.Count) then
		raise EArgumentException.Create('Version index out of range');
end;

function VersionIndex(ASession: TConversationSession; const AOptions: TCliOptions): Integer;
begin
	Result := AOptions.VersionIndex;
	if Result < 0 then
		Result := ASession.LatestVersionIndex;
end;

procedure ShowRunSettings(ASettings: TGeminiRunSettings);
var
	I: Integer;
begin
	WriteLn('Model: ', ASettings.Model);
	if not IsNaN(ASettings.Temperature) then
		WriteLn('Temperature: ', FormatFloat('0.0#', ASettings.Temperature, TFormatSettings.Invariant));
	if not IsNaN(ASettings.TopP) then
		WriteLn('TopP: ', FormatFloat('0.0#', ASettings.TopP, TFormatSettings.Invariant));
	if ASettings.TopK >= 0 then
		WriteLn('TopK: ', ASettings.TopK);
	if ASettings.MaxOutputTokens >= 0 then
		WriteLn('MaxOutputTokens: ', ASettings.MaxOutputTokens);
	if ASettings.ResponseMimeType <> '' then
		WriteLn('ResponseMimeType: ', ASettings.ResponseMimeType);
	if Length(ASettings.ResponseModalities) > 0 then
		WriteLn('ResponseModalities: ', string.Join(', ', ASettings.ResponseModalities));
	for I := 0 to High(ASettings.SafetySettings) do
		WriteLn('Safety setting: ', ASettings.SafetySettings[I].Category, ' = ', ASettings.SafetySettings[I].Threshold);
	if ASettings.EnableCodeExecution then
		WriteLn('Code execution: enabled');
	if ASettings.EnableSearchAsATool then
		WriteLn('Search as tool: enabled');
	if ASettings.EnableBrowseAsATool then
		WriteLn('Browse as tool: enabled');
	if ASettings.EnableAutoFunctionResponse then
		WriteLn('Auto func resp: enabled');
end;

procedure ShowInfo(AFile: TConversationFile; const AOptions: TCliOptions; AVersionsOnly: Boolean);
var
	I, J: Integer;
	LSession: TConversationSession;
	LData: TGeminiFile;
begin
	WriteLn('Sessions: ', AFile.Sessions.Count);
	for I := 0 to AFile.Sessions.Count - 1 do
	begin
		if (AOptions.SessionIndex >= 0) and (AOptions.SessionIndex <> I) then
			Continue;
		LSession := AFile.Sessions[I];
		WriteLn;
		WriteLn('[', I + 1, '] ', LSession.Title);
		if AFile.IsClaude then
			WriteLn(LSession.Metadata);
		for J := 0 to LSession.Versions.Count - 1 do
			if (AOptions.VersionIndex < 0) or (AOptions.VersionIndex = J) then
				WriteLn('  Version ', J + 1, ': ', FormatCreateTime(LSession.Versions[J].SavedAt),
					' UTC, ', LSession.Versions[J].Conversation.ChunkCount, ' chunks');
		if AVersionsOnly then
			Continue;
		LData := LSession.Versions[VersionIndex(LSession, AOptions)].Conversation;
		ShowRunSettings(LData.RunSettings);
		WriteLn('Total chunks: ', LData.ChunkCount, ' (user: ', LData.UserChunkCount, ', model: ', LData.ModelChunkCount, ')');
		WriteLn('Total tokens: ', LData.TotalTokenCount);
		WriteLn('Embedded resources: ', LData.GetResourceCount);
		if AFile.IsClaude then
			WriteLn('Settings: ', LSession.Versions[VersionIndex(LSession, AOptions)].Settings);
		if LData.SystemInstruction <> '' then
			WriteLn('System instruction: ', Copy(LData.SystemInstruction, 1, 500));
	end;
end;

procedure ExportConversation(AFile: TConversationFile; const AFileName: string; const AOptions: TCliOptions);
var
	LFormatter: TConversationFormatter;
	LStream: TStream;
begin
	LFormatter := TConversationFormatter.Create;
	try
		LFormatter.HtmlConfig.EmbedResources := True;
		LFormatter.HtmlConfig.RemoteImages := AOptions.Images;
		LFormatter.HtmlConfig.SourceFileName := TPath.GetFileNameWithoutExtension(AFileName);
		if AOptions.OutputPath = '' then
		begin
			Flush(Output);
			LStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
		end
		else
			LStream := TFileStream.Create(AOptions.OutputPath, fmCreate);
		try
			LFormatter.FormatToStream(LStream, AFile, AOptions.ExportFormat, AOptions.SessionIndex, AOptions.VersionIndex);
		finally
			LStream.Free;
		end;
	finally
		LFormatter.Free;
	end;
end;

procedure ProcessResources(AFile: TConversationFile; const AFileName: string; const AOptions: TCliOptions; AExtract: Boolean);
var
	I, J, LVersion, LCount: Integer;
	LSession: TConversationSession;
	LData: TGeminiFile;
	LResources: TArray<TGeminiResource>;
	LChunk: TGeminiChunk;
	LBaseDir, LDir: string;
begin
	LCount := 0;
	LBaseDir := AOptions.OutputPath;
	if LBaseDir = '' then
		LBaseDir := TPath.ChangeExtension(TPath.GetFullPath(AFileName), '') + '_resources';
	for I := 0 to AFile.Sessions.Count - 1 do
	begin
		if (AOptions.SessionIndex >= 0) and (AOptions.SessionIndex <> I) then
			Continue;
		LSession := AFile.Sessions[I];
		LVersion := VersionIndex(LSession, AOptions);
		LData := LSession.Versions[LVersion].Conversation;
		if AExtract then
		begin
			LDir := LBaseDir;
			if AFile.IsClaude then
				LDir := TPath.Combine(LBaseDir, StringReplace(SessionResourcePrefix(LSession, I, LVersion) + 'resources', '/', PathDelim, [rfReplaceAll]));
			Inc(LCount, LData.ExtractAllResources(LDir, not AOptions.Sequential, AOptions.Prefix));
		end
		else
		begin
			WriteLn('[', I + 1, '] ', LSession.Title, ' / Version ', LVersion + 1);
			LResources := LData.GetResources;
			if Length(LResources) > 0 then
				WriteLn('Index  Chunk#  MIME Type  Base64 size  Estimated size  Extension');
			for J := 0 to High(LResources) do
				WriteLn(J, '  ', LResources[J].ChunkIndex, '  ', LResources[J].MimeType, '  ',
					FormatByteSize(LResources[J].Base64Size), '  ', FormatByteSize(LResources[J].DecodedSize), '  ', LResources[J].GetFileExtension);
			for LChunk in LData.Chunks do
				if LChunk.RemoteImageUrl <> '' then
					WriteLn('  Remote image: ', LChunk.RemoteImageUrl);
			Inc(LCount, Length(LResources));
		end;
	end;
	if AExtract then
		WriteLn('Extracted ', LCount, ' embedded resource(s) to ', LBaseDir)
	else
		WriteLn('Embedded resources: ', LCount);
end;

var
	LCommand, LFileName: string;
	LFile: TConversationFile;
	LOptions: TCliOptions;
begin
	SetConsoleOutputCP(CP_UTF8);
	SetTextCodePage(Output, CP_UTF8);
	try
		if (ParamCount = 0) or SameText(ParamStr(1), 'help') or SameText(ParamStr(1), '--help') or SameText(ParamStr(1), '-h') then
		begin
			PrintHelp;
			Exit;
		end;
		if ParamCount < 2 then
			raise EArgumentException.Create('Missing file argument');
		LCommand := LowerCase(ParamStr(1));
		if (LCommand <> 'info') and (LCommand <> 'sessions') and (LCommand <> 'conversation') and
			(LCommand <> 'export') and (LCommand <> 'resources') and (LCommand <> 'res') and (LCommand <> 'extract') then
			raise EArgumentException.Create('Unknown command: ' + LCommand);
		LOptions := ReadOptions(LCommand);
		LFileName := ParamStr(2);
		LFile := TConversationFile.Create;
		try
			LFile.LoadFromFile(LFileName);
			ValidateSelection(LFile, LOptions);
			if (LCommand = 'info') or (LCommand = 'sessions') then
			begin
				WriteLn('File: ', LFileName);
				WriteLn('File size: ', FormatByteSize(TFile.GetSize(LFileName)));
				ShowInfo(LFile, LOptions, LCommand = 'sessions');
			end
			else if (LCommand = 'conversation') or (LCommand = 'export') then
				ExportConversation(LFile, LFileName, LOptions)
			else
				ProcessResources(LFile, LFileName, LOptions, LCommand = 'extract');
		finally
			LFile.Free;
		end;
	except
		on E: Exception do
		begin
			WriteLn(ErrOutput, 'Error: ', E.Message);
			ExitCode := 1;
		end;
	end;
end.
