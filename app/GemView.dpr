/// <summary>
///   GemView -- Console application for viewing and extracting data from
///   Google Gemini AI Studio conversation files.
///
///   Usage:
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
  System.Math,
  System.IOUtils,
  GeminiFile in '..\src\GeminiFile.pas';

const
  APP_VERSION = '0.1.0';

/// <summary>Formats a byte size as a human-readable string.</summary>
function FormatSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := Format('%d B', [ASize])
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f KB', [ASize / 1024.0])
  else if ASize < Int64(1024) * 1024 * 1024 then
    Result := Format('%.1f MB', [ASize / (1024.0 * 1024.0)])
  else
    Result := Format('%.2f GB', [ASize / (1024.0 * 1024.0 * 1024.0)]);
end;

/// <summary>Prints usage information.</summary>
procedure PrintHelp;
begin
  WriteLn('GemView v', APP_VERSION, ' -- Gemini conversation file viewer/extractor');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  gemview info <file>                Show file metadata and statistics');
  WriteLn('  gemview conversation <file>        Print the conversation text');
  WriteLn('  gemview resources <file>           List embedded resources');
  WriteLn('  gemview extract <file> [options]   Extract embedded resources');
  WriteLn('  gemview help                       Show this help');
  WriteLn;
  WriteLn('Extract options:');
  WriteLn('  --output <dir>      Output directory (default: <filename>_resources)');
  WriteLn('  --sequential        Single-threaded extraction');
  WriteLn('  --prefix <name>     Filename prefix (default: resource)');
end;

/// <summary>Loads a Gemini file, handling errors gracefully.</summary>
/// <param name="AFileName">Path to the file.</param>
/// <param name="AGemFile">Output: loaded TGeminiFile instance.</param>
/// <returns>True if loaded successfully, False on error.</returns>
function TryLoadFile(const AFileName: string; out AGemFile: TGeminiFile): Boolean;
begin
  Result := False;
  AGemFile := TGeminiFile.Create;
  try
    AGemFile.LoadFromFile(AFileName);
    Result := True;
  except
    on E: EFileNotFoundException do
    begin
      WriteLn('Error: ', E.Message);
      FreeAndNil(AGemFile);
    end;
    on E: EGeminiParseError do
    begin
      WriteLn('Error: Failed to parse Gemini file: ', E.Message);
      FreeAndNil(AGemFile);
    end;
    on E: Exception do
    begin
      WriteLn('Error: ', E.ClassName, ': ', E.Message);
      FreeAndNil(AGemFile);
    end;
  end;
end;

/// <summary>
///   Executes the 'info' command: displays file metadata and statistics.
/// </summary>
procedure CmdInfo(const AFileName: string);
var
  LFile: TGeminiFile;
  LResources: TArray<TGeminiResource>;
  I: Integer;
  LTotalResSize: Int64;
  LSysInstr: string;
begin
  if not TryLoadFile(AFileName, LFile) then
    Exit;
  try
    WriteLn('File: ', AFileName);
    WriteLn('File size: ', FormatSize(TFile.GetSize(AFileName)));
    WriteLn;

    // Run settings
    WriteLn('=== Model Settings ===');
    WriteLn('Model:             ', LFile.RunSettings.Model);
    if not IsNaN(LFile.RunSettings.Temperature) then
      WriteLn('Temperature:       ', FormatFloat('0.0#', LFile.RunSettings.Temperature));
    if not IsNaN(LFile.RunSettings.TopP) then
      WriteLn('TopP:              ', FormatFloat('0.0#', LFile.RunSettings.TopP));
    if LFile.RunSettings.TopK >= 0 then
      WriteLn('TopK:              ', LFile.RunSettings.TopK);
    if LFile.RunSettings.MaxOutputTokens >= 0 then
      WriteLn('MaxOutputTokens:   ', LFile.RunSettings.MaxOutputTokens);
    if LFile.RunSettings.ResponseMimeType <> '' then
      WriteLn('ResponseMimeType:  ', LFile.RunSettings.ResponseMimeType);
    if Length(LFile.RunSettings.ResponseModalities) > 0 then
      WriteLn('ResponseModalities:', string.Join(', ', LFile.RunSettings.ResponseModalities));
    if Length(LFile.RunSettings.SafetySettings) > 0 then
    begin
      WriteLn('Safety settings:   ', Length(LFile.RunSettings.SafetySettings), ' rules');
      for I := 0 to High(LFile.RunSettings.SafetySettings) do
        WriteLn('  ', LFile.RunSettings.SafetySettings[I].Category, ' = ',
          LFile.RunSettings.SafetySettings[I].Threshold);
    end;

    // Feature flags
    if LFile.RunSettings.EnableCodeExecution then
      WriteLn('Code execution:    enabled');
    if LFile.RunSettings.EnableSearchAsATool then
      WriteLn('Search as tool:    enabled');
    if LFile.RunSettings.EnableBrowseAsATool then
      WriteLn('Browse as tool:    enabled');
    if LFile.RunSettings.EnableAutoFunctionResponse then
      WriteLn('Auto func resp:    enabled');

    WriteLn;

    // System instruction
    WriteLn('=== System Instruction ===');
    if LFile.SystemInstruction <> '' then
    begin
      LSysInstr := LFile.SystemInstruction;
      if Length(LSysInstr) > 500 then
        LSysInstr := Copy(LSysInstr, 1, 500) + '... [truncated, ' +
          FormatSize(Length(LFile.SystemInstruction) * SizeOf(Char)) + ' total]';
      WriteLn(LSysInstr);
    end
    else
      WriteLn('(none)');

    WriteLn;

    // Conversation stats
    WriteLn('=== Conversation ===');
    WriteLn('Total chunks:      ', LFile.ChunkCount);
    WriteLn('User chunks:       ', LFile.UserChunkCount);
    WriteLn('Model chunks:      ', LFile.ModelChunkCount);
    WriteLn('Total tokens:      ', LFile.TotalTokenCount);

    WriteLn;

    // Resources
    LResources := LFile.GetResources;
    WriteLn('=== Embedded Resources ===');
    WriteLn('Resource count:    ', Length(LResources));
    if Length(LResources) > 0 then
    begin
      LTotalResSize := 0;
      for I := 0 to High(LResources) do
        Inc(LTotalResSize, LResources[I].DecodedSize);
      WriteLn('Total est. size:   ', FormatSize(LTotalResSize));
    end;
  finally
    LFile.Free;
  end;
end;

/// <summary>
///   Executes the 'conversation' command: prints the conversation text.
/// </summary>
procedure CmdConversation(const AFileName: string);
var
  LFile: TGeminiFile;
  LChunk: TGeminiChunk;
  LText: string;
  LRes: TGeminiResource;
begin
  if not TryLoadFile(AFileName, LFile) then
    Exit;
  try
    for LChunk in LFile.Chunks do
    begin
      // Header
      case LChunk.Role of
        grUser:
          Write('[USER]');
        grModel:
        begin
          if LChunk.IsThought then
            Write('[THOUGHT]')
          else
            Write('[MODEL]');
        end;
      end;

      // Metadata annotations
      if LChunk.TokenCount > 0 then
        Write(' (', LChunk.TokenCount, ' tokens)');
      if LChunk.FinishReason <> '' then
        Write(' [', LChunk.FinishReason, ']');
      if LChunk.ErrorMessage <> '' then
        Write(' [ERROR: ', LChunk.ErrorMessage, ']');
      WriteLn;

      // Text content
      if LChunk.IsThought then
        LText := LChunk.GetThinkingText
      else
        LText := LChunk.GetFullText;

      if LText <> '' then
        WriteLn(LText);

      // Resource indicator
      if LChunk.HasResource then
      begin
        LRes := LChunk.GetResource;
        if LRes <> nil then
          WriteLn('[IMAGE: ', LRes.MimeType, ', ~', FormatSize(LRes.DecodedSize), ']');
      end;

      // Drive image reference
      if LChunk.DriveImageId <> '' then
        WriteLn('[DRIVE IMAGE: id=', LChunk.DriveImageId, ']');

      WriteLn;
    end;
  finally
    LFile.Free;
  end;
end;

/// <summary>
///   Executes the 'resources' command: lists all embedded resources.
/// </summary>
procedure CmdResources(const AFileName: string);
var
  LFile: TGeminiFile;
  LResources: TArray<TGeminiResource>;
  I: Integer;
  LTotalSize: Int64;
begin
  if not TryLoadFile(AFileName, LFile) then
    Exit;
  try
    LResources := LFile.GetResources;
    if Length(LResources) = 0 then
    begin
      WriteLn('No embedded resources found.');
      Exit;
    end;

    WriteLn('Embedded resources in: ', AFileName);
    WriteLn;
    WriteLn(Format('%-6s  %-8s  %-16s  %-12s  %-12s  %s',
      ['Index', 'Chunk#', 'MIME Type', 'B64 Size', 'Est. Size', 'Extension']));
    WriteLn(StringOfChar('-', 76));

    LTotalSize := 0;
    for I := 0 to High(LResources) do
    begin
      WriteLn(Format('%-6d  %-8d  %-16s  %-12s  %-12s  %s', [
        I,
        LResources[I].ChunkIndex,
        LResources[I].MimeType,
        FormatSize(LResources[I].Base64Size),
        FormatSize(LResources[I].DecodedSize),
        LResources[I].GetFileExtension
      ]));
      Inc(LTotalSize, LResources[I].DecodedSize);
    end;

    WriteLn(StringOfChar('-', 76));
    WriteLn(Format('Total: %d resources, ~%s estimated', [Length(LResources), FormatSize(LTotalSize)]));
  finally
    LFile.Free;
  end;
end;

/// <summary>
///   Executes the 'extract' command: extracts all embedded resources to files.
/// </summary>
procedure CmdExtract(const AFileName: string);
var
  LFile: TGeminiFile;
  LOutputDir: string;
  LPrefix: string;
  LThreaded: Boolean;
  LCount: Integer;
  I: Integer;
  LParam: string;
begin
  // Parse options
  LOutputDir := '';
  LPrefix := 'resource';
  LThreaded := True;

  I := 3; // params start after command and filename
  while I <= ParamCount do
  begin
    LParam := ParamStr(I);
    if SameText(LParam, '--output') and (I < ParamCount) then
    begin
      Inc(I);
      LOutputDir := ParamStr(I);
    end
    else if SameText(LParam, '--sequential') then
      LThreaded := False
    else if SameText(LParam, '--prefix') and (I < ParamCount) then
    begin
      Inc(I);
      LPrefix := ParamStr(I);
    end
    else
      WriteLn('Warning: unknown option: ', LParam);
    Inc(I);
  end;

  // Default output directory
  if LOutputDir = '' then
    LOutputDir := TPath.Combine(
      TPath.GetDirectoryName(TPath.GetFullPath(AFileName)),
      TPath.GetFileNameWithoutExtension(AFileName) + '_resources');

  if not TryLoadFile(AFileName, LFile) then
    Exit;
  try
    LFile.OnExtractProgress :=
      procedure(AIndex, ATotal: Integer; const AFN: string)
      begin
        WriteLn(Format('  [%d/%d] %s', [AIndex + 1, ATotal, TPath.GetFileName(AFN)]));
      end;

    WriteLn('Extracting resources from: ', AFileName);
    WriteLn('Output directory: ', LOutputDir);
    if LThreaded then
      WriteLn('Mode: threaded')
    else
      WriteLn('Mode: sequential');
    WriteLn;

    LCount := LFile.ExtractAllResources(LOutputDir, LThreaded, LPrefix);

    if LCount = 0 then
      WriteLn('No embedded resources found.')
    else
      WriteLn(Format('Done. Extracted %d resource(s).', [LCount]));
  finally
    LFile.Free;
  end;
end;

/// <summary>Main entry point.</summary>
var
  LCommand: string;
  LFileName: string;
begin
  try
    // Set UTF-8 console output
    SetConsoleOutputCP(65001);

    if ParamCount < 1 then
    begin
      PrintHelp;
      ExitCode := 1;
      Exit;
    end;

    LCommand := LowerCase(ParamStr(1));

    if (LCommand = 'help') or (LCommand = '--help') or (LCommand = '-h') then
    begin
      PrintHelp;
      Exit;
    end;

    if ParamCount < 2 then
    begin
      WriteLn('Error: missing file argument.');
      WriteLn;
      PrintHelp;
      ExitCode := 1;
      Exit;
    end;

    LFileName := ParamStr(2);

    if LCommand = 'info' then
      CmdInfo(LFileName)
    else if LCommand = 'conversation' then
      CmdConversation(LFileName)
    else if (LCommand = 'resources') or (LCommand = 'res') then
      CmdResources(LFileName)
    else if LCommand = 'extract' then
      CmdExtract(LFileName)
    else
    begin
      WriteLn('Error: unknown command "', LCommand, '"');
      WriteLn;
      PrintHelp;
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      WriteLn('Fatal error: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
