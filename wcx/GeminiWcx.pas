/// <summary>
///   WCX plugin implementation for Gemini conversation files.
///   Exposes Gemini files as virtual archives with conversation exports
///   (txt, md, html) and extracted resources. Implements both Unicode
///   and ANSI variants of the WCX API.
/// </summary>
unit GeminiWcx;

interface

uses
	Winapi.Windows,
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.IniFiles,
	System.Math,
	System.Generics.Collections,
	System.AnsiStrings,
	WcxApi,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Parser,
	GeminiFile.Extractor,
	GeminiFile,
	GeminiFile.Formatter.Intf,
	GeminiFile.Formatter.Text,
	GeminiFile.Formatter.Md,
	GeminiFile.Formatter.Html,
	GeminiPlugin.Shared;

type
	TVirtualFileKind = (vfConversationText, vfConversationMarkdown, vfConversationHtml, vfConversationHtmlEmbedded, vfResourceDir, vfResource);

	TVirtualFileEntry = record
		Path: string;
		Kind: TVirtualFileKind;
		UnpackedSize: Int64;
		FileTime: Integer;
		ResourceIndex: Integer;
	end;

	/// <summary>
	///   Manages a single opened Gemini archive. Created by OpenArchiveW,
	///   iterated by ReadHeaderExW/ProcessFileW, destroyed by CloseArchive.
	/// </summary>
	TGeminiArchive = class
	private
		FGeminiFile: TGeminiFile;
		FFileName: string;
		FBaseName: string;
		FOpenMode: Integer;
		FVirtualFiles: TList<TVirtualFileEntry>;
		FCurrentIndex: Integer;
		FResources: TArray<TGeminiResource>;
		FResourceInfos: TArray<TFormatterResourceInfo>;
		FFileTime: Integer;
		// Cached generated content
		FCachedText: TBytes;
		FCachedMarkdown: TBytes;
		FCachedHtml: TBytes;
		// Callbacks
		FProcessDataProc: TProcessDataProcW;
		FChangeVolProc: TChangeVolProcW;
		procedure AddVirtualFile(const APath: string; AKind: TVirtualFileKind; ASize: Int64; AResourceIndex: Integer = -1);
		procedure BuildVirtualFileList;
		procedure CacheFormattedContent;
		/// <summary>Formats a conversation using the given formatter and returns the result as bytes.</summary>
		function FormatToBytes(const AFormatter: IGeminiFormatter): TBytes;
		function EstimateEmbeddedHtmlSize: Int64;
		function ExtractVirtualFile(const AEntry: TVirtualFileEntry; const ADestPath: string): Integer;
		function WriteBytesToFile(const AData: TBytes; const AFilePath: string): Integer;
		procedure ReportProgress(const AFileName: string; ASize: Integer);
	public
		/// <summary>Creates and initializes a Gemini archive for reading.</summary>
		/// <param name="AFileName">Full path to the Gemini file.</param>
		/// <param name="AOpenMode">PK_OM_LIST or PK_OM_EXTRACT.</param>
		/// <exception cref="Exception">If the file cannot be parsed.</exception>
		constructor Create(const AFileName: string; AOpenMode: Integer);
		destructor Destroy; override;

		/// <summary>Fills the next header and advances the iterator.</summary>
		/// <returns>0 on success, E_END_ARCHIVE when done.</returns>
		function ReadNextHeader(var AHeader: THeaderDataExW): Integer;

		/// <summary>Processes the current file (skip, test, or extract).</summary>
		/// <param name="AOperation">PK_SKIP, PK_TEST, or PK_EXTRACT.</param>
		/// <param name="ADestPath">Destination directory path.</param>
		/// <param name="ADestName">Destination file name (full path).</param>
		/// <returns>0 on success, error code on failure.</returns>
		function ProcessCurrentFile(AOperation: Integer; const ADestPath, ADestName: string): Integer;

		property ProcessDataProc: TProcessDataProcW write FProcessDataProc;
		property ChangeVolProc: TChangeVolProcW write FChangeVolProc;
	end;

	TPluginConfig = record
		UseOriginalName: Boolean;
		EnableText: Boolean;
		EnableMarkdown: Boolean;
		EnableHtml: Boolean;
		EnableHtmlEmbedded: Boolean;
		HideEmptyBlocksText: Boolean;
		HideEmptyBlocksMd: Boolean;
		HideEmptyBlocksHtml: Boolean;
		DefaultFullWidth: Boolean;
		DefaultExpandThinking: Boolean;
		RenderMarkdown: Boolean;
		CombineBlocksText: Boolean;
		CombineBlocksMd: Boolean;
		CombineBlocksHtml: Boolean;
		CollapseSystemInstruction: Boolean;
	end;

	/// <summary>
	///   Returns the plugin configuration, reading from gemini.ini on first call.
	///   The INI file is expected next to the plugin DLL. Missing file = defaults.
	/// </summary>
function GetPluginConfig: TPluginConfig;

/// <summary>
///   Returns the base name for virtual conversation files.
///   Pure function for testability.
/// </summary>
/// <param name="AFileName">Full path to the source Gemini file.</param>
/// <param name="AUseOriginalName">If True, uses the file's own name; otherwise 'conversation'.</param>
function GetBaseName(const AFileName: string; AUseOriginalName: Boolean): string;

// --- Exported WCX functions ---

// Unicode (primary)
function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;
function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;
function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath: PWideChar; DestName: PWideChar): Integer; stdcall;
function CloseArchive(hArcData: THandle): Integer; stdcall;
procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;
function GetPackerCaps: Integer; stdcall;
function CanYouHandleThisFileW(FileName: PWideChar): LongBool; stdcall;
function GetBackgroundFlags: Integer; stdcall;

// ANSI (compatibility)
function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
function ReadHeaderEx(hArcData: THandle; var HeaderData: THeaderDataEx): Integer; stdcall;
function ProcessFile(hArcData: THandle; Operation: Integer; DestPath: PAnsiChar; DestName: PAnsiChar): Integer; stdcall;
procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
function CanYouHandleThisFile(FileName: PAnsiChar): LongBool; stdcall;

implementation

const
	/// Default plugin configuration values (single source of truth)
	DEF_UseOriginalName = True;
	DEF_EnableText = True;
	DEF_EnableMarkdown = True;
	DEF_EnableHtml = True;
	DEF_EnableHtmlEmbedded = True;
	DEF_HideEmptyBlocksText = True;
	DEF_HideEmptyBlocksMd = True;
	DEF_HideEmptyBlocksHtml = True;
	DEF_DefaultFullWidth = False;
	DEF_DefaultExpandThinking = False;
	DEF_RenderMarkdown = True;
	DEF_CombineBlocksText = False;
	DEF_CombineBlocksMd = False;
	DEF_CombineBlocksHtml = False;
	DEF_CollapseSystemInstruction = True;

var
	/// Tracks live archive handles for validation (thread-safe for background unpack)
	GArchives: TThreadList<TGeminiArchive>;
	/// Cached plugin configuration from gemini.ini
	GPluginConfig: TPluginConfig;
	GPluginConfigLoaded: Boolean;

function GetPluginConfig: TPluginConfig;
var
	LIniPath: string;
	LIni: TIniFile;
	LHtmlDefaults: TSharedHtmlDefaults;
begin
	if not GPluginConfigLoaded then
	begin
		GPluginConfigLoaded := True;
		// Defaults from constants (single source of truth)
		GPluginConfig := Default (TPluginConfig);
		GPluginConfig.UseOriginalName := DEF_UseOriginalName;
		GPluginConfig.EnableText := DEF_EnableText;
		GPluginConfig.EnableMarkdown := DEF_EnableMarkdown;
		GPluginConfig.EnableHtml := DEF_EnableHtml;
		GPluginConfig.EnableHtmlEmbedded := DEF_EnableHtmlEmbedded;
		GPluginConfig.HideEmptyBlocksText := DEF_HideEmptyBlocksText;
		GPluginConfig.HideEmptyBlocksMd := DEF_HideEmptyBlocksMd;
		GPluginConfig.HideEmptyBlocksHtml := DEF_HideEmptyBlocksHtml;
		GPluginConfig.RenderMarkdown := DEF_RenderMarkdown;
		GPluginConfig.CollapseSystemInstruction := DEF_CollapseSystemInstruction;

		LIniPath := TPath.Combine(GetPluginDir, 'gemini.ini');
		if TFile.Exists(LIniPath) then
		begin
			LIni := TIniFile.Create(LIniPath);
			try
				GPluginConfig.UseOriginalName := LIni.ReadBool('General', 'UseOriginalName', DEF_UseOriginalName);
				GPluginConfig.EnableText := LIni.ReadBool('Formatters', 'EnableText', DEF_EnableText);
				GPluginConfig.EnableMarkdown := LIni.ReadBool('Formatters', 'EnableMarkdown', DEF_EnableMarkdown);
				GPluginConfig.EnableHtml := LIni.ReadBool('Formatters', 'EnableHtml', DEF_EnableHtml);
				GPluginConfig.EnableHtmlEmbedded := LIni.ReadBool('Formatters', 'EnableHtmlEmbedded', DEF_EnableHtmlEmbedded);
				GPluginConfig.HideEmptyBlocksText := LIni.ReadBool('Formatters', 'HideEmptyBlocksText', DEF_HideEmptyBlocksText);
				GPluginConfig.HideEmptyBlocksMd := LIni.ReadBool('Formatters', 'HideEmptyBlocksMd', DEF_HideEmptyBlocksMd);
				GPluginConfig.HideEmptyBlocksHtml := LIni.ReadBool('Formatters', 'HideEmptyBlocksHtml', DEF_HideEmptyBlocksHtml);
				GPluginConfig.CombineBlocksText := LIni.ReadBool('Formatters', 'CombineBlocksText', DEF_CombineBlocksText);
				GPluginConfig.CombineBlocksMd := LIni.ReadBool('Formatters', 'CombineBlocksMd', DEF_CombineBlocksMd);
				GPluginConfig.CombineBlocksHtml := LIni.ReadBool('Formatters', 'CombineBlocksHtml', DEF_CombineBlocksHtml);
				ReadHtmlDefaults(LIni, DEF_DefaultFullWidth, DEF_DefaultExpandThinking,
					DEF_RenderMarkdown, DEF_CollapseSystemInstruction, LHtmlDefaults);
				GPluginConfig.DefaultFullWidth := LHtmlDefaults.DefaultFullWidth;
				GPluginConfig.DefaultExpandThinking := LHtmlDefaults.DefaultExpandThinking;
				GPluginConfig.RenderMarkdown := LHtmlDefaults.RenderMarkdown;
				GPluginConfig.CollapseSystemInstruction := LHtmlDefaults.CollapseSystemInstruction;
			finally
				LIni.Free;
			end;
		end;
	end;
	Result := GPluginConfig;
end;

function GetBaseName(const AFileName: string; AUseOriginalName: Boolean): string;
begin
	if AUseOriginalName then
		Result := TPath.GetFileNameWithoutExtension(AFileName)
	else
		Result := 'conversation';
end;

function IsValidHandle(hArcData: THandle): Boolean;
var
	LList: TList<TGeminiArchive>;
begin
	if hArcData = 0 then
		Exit(False);
	LList := GArchives.LockList;
	try
		Result := LList.Contains(TGeminiArchive(hArcData));
	finally
		GArchives.UnlockList;
	end;
end;

/// <summary>
///   Converts a file modification time to DOS timestamp format.
/// </summary>
function GetDosFileTime(const AFileName: string): Integer;
var
	LDateTime: TDateTime;
begin
	if FileAge(AFileName, LDateTime) then
		Result := DateTimeToFileDate(LDateTime)
	else
		Result := 0;
end;

{TGeminiArchive}

constructor TGeminiArchive.Create(const AFileName: string; AOpenMode: Integer);
begin
	inherited Create;
	FFileName := AFileName;
	FBaseName := GetBaseName(AFileName, GetPluginConfig.UseOriginalName);
	FOpenMode := AOpenMode;
	FVirtualFiles := TList<TVirtualFileEntry>.Create;
	FCurrentIndex := 0;

	FFileTime := GetDosFileTime(AFileName);

	FGeminiFile := TGeminiFile.Create;
	FGeminiFile.LoadFromFile(AFileName);

	FResources := FGeminiFile.GetResources;
	FResourceInfos := BuildFormatterResourceInfos(FResources, FGeminiFile.Chunks);
	CacheFormattedContent;
	BuildVirtualFileList;
end;

destructor TGeminiArchive.Destroy;
begin
	FreeAndNil(FVirtualFiles);
	FreeAndNil(FGeminiFile);
	inherited;
end;

/// <summary>Copies the full contents of a memory stream into a byte array.</summary>
function StreamToBytes(AStream: TMemoryStream): TBytes;
begin
	SetLength(Result, AStream.Size);
	if AStream.Size > 0 then
	begin
		AStream.Position := 0;
		AStream.ReadBuffer(Result[0], AStream.Size);
	end;
end;

/// <summary>Builds an HTML formatter config from WCX plugin config.</summary>
function BuildWcxHtmlConfig(const AConfig: TPluginConfig; AEmbedResources: Boolean;
	const ASourceFileName, ACustomCSS: string): TGeminiHtmlFormatterConfig;
var
	LDefaults: TSharedHtmlDefaults;
begin
	LDefaults.DefaultFullWidth := AConfig.DefaultFullWidth;
	LDefaults.DefaultExpandThinking := AConfig.DefaultExpandThinking;
	LDefaults.RenderMarkdown := AConfig.RenderMarkdown;
	LDefaults.CollapseSystemInstruction := AConfig.CollapseSystemInstruction;
	Result := BuildHtmlFormatterConfig(AEmbedResources, ASourceFileName, ACustomCSS,
		AConfig.HideEmptyBlocksHtml, AConfig.CombineBlocksHtml, LDefaults);
end;

function TGeminiArchive.FormatToBytes(const AFormatter: IGeminiFormatter): TBytes;
var
	LStream: TMemoryStream;
begin
	LStream := TMemoryStream.Create;
	try
		AFormatter.FormatToStream(LStream, FGeminiFile.Chunks, FGeminiFile.SystemInstruction, FGeminiFile.RunSettings, FResourceInfos);
		Result := StreamToBytes(LStream);
	finally
		LStream.Free;
	end;
end;

procedure TGeminiArchive.CacheFormattedContent;
var
	LTextFmt: TGeminiTextFormatter;
	LMdFmt: TGeminiMarkdownFormatter;
	LFmt: IGeminiFormatter;
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;

	// Plain text -- interface variable manages lifetime via ref-counting
	LTextFmt := TGeminiTextFormatter.Create;
	LTextFmt.SourceFileName := TPath.GetFileNameWithoutExtension(FFileName);
	LTextFmt.HideEmptyBlocks := LConfig.HideEmptyBlocksText;
	LTextFmt.CombineBlocks := LConfig.CombineBlocksText;
	LFmt := LTextFmt;
	FCachedText := FormatToBytes(LFmt);

	// Markdown
	LMdFmt := TGeminiMarkdownFormatter.Create;
	LMdFmt.SourceFileName := TPath.GetFileNameWithoutExtension(FFileName);
	LMdFmt.HideEmptyBlocks := LConfig.HideEmptyBlocksMd;
	LMdFmt.CombineBlocks := LConfig.CombineBlocksMd;
	LFmt := LMdFmt;
	FCachedMarkdown := FormatToBytes(LFmt);

	// HTML (external resources)
	LFmt := TGeminiHtmlFormatter.Create(BuildWcxHtmlConfig(LConfig, False, TPath.GetFileNameWithoutExtension(FFileName), LoadCustomCSS));
	FCachedHtml := FormatToBytes(LFmt);
end;

function TGeminiArchive.EstimateEmbeddedHtmlSize: Int64;
var
	I: Integer;
begin
	Result := Length(FCachedHtml);
	// Estimate base64 size from decoded size (base64 expands by ~4/3)
	for I := 0 to High(FResourceInfos) do
		Inc(Result, (FResourceInfos[I].DecodedSize * 4) div 3 + 100);
end;

procedure TGeminiArchive.AddVirtualFile(const APath: string; AKind: TVirtualFileKind; ASize: Int64; AResourceIndex: Integer);
var
	LEntry: TVirtualFileEntry;
begin
	LEntry := Default (TVirtualFileEntry);
	LEntry.Path := APath;
	LEntry.Kind := AKind;
	LEntry.UnpackedSize := ASize;
	LEntry.FileTime := FFileTime;
	LEntry.ResourceIndex := AResourceIndex;
	FVirtualFiles.Add(LEntry);
end;

procedure TGeminiArchive.BuildVirtualFileList;
var
	I: Integer;
	LHasThinkingResources: Boolean;
	LConfig: TPluginConfig;
begin
	FVirtualFiles.Clear;
	LConfig := GetPluginConfig;

	if LConfig.EnableText then
		AddVirtualFile(FBaseName + '.txt', vfConversationText, Length(FCachedText));
	if LConfig.EnableMarkdown then
		AddVirtualFile(FBaseName + '.md', vfConversationMarkdown, Length(FCachedMarkdown));
	if LConfig.EnableHtml then
		AddVirtualFile(FBaseName + '.html', vfConversationHtml, Length(FCachedHtml));

	if Length(FResources) > 0 then
	begin
		if LConfig.EnableHtmlEmbedded then
			AddVirtualFile(FBaseName + '_full.html', vfConversationHtmlEmbedded, EstimateEmbeddedHtmlSize);

		AddVirtualFile('resources', vfResourceDir, 0);

		// resources\think\ subdirectory (only if thinking resources exist)
		LHasThinkingResources := False;
		for I := 0 to High(FResourceInfos) do
			if FResourceInfos[I].IsThinking then
			begin
				LHasThinkingResources := True;
				Break;
			end;
		if LHasThinkingResources then
			AddVirtualFile('resources\think', vfResourceDir, 0);

		// Individual resources -- paths derived from FResourceInfos (single source of truth)
		for I := 0 to High(FResourceInfos) do
			AddVirtualFile(StringReplace(FResourceInfos[I].FileName, '/', '\', [rfReplaceAll]), vfResource, FResourceInfos[I].DecodedSize, I);
	end;
end;

function TGeminiArchive.ReadNextHeader(var AHeader: THeaderDataExW): Integer;
var
	LEntry: TVirtualFileEntry;
	LPath: string;
begin
	if FCurrentIndex >= FVirtualFiles.Count then
		Exit(E_END_ARCHIVE);

	LEntry := FVirtualFiles[FCurrentIndex];

	FillChar(AHeader, SizeOf(AHeader), 0);

	// Copy archive name
	StrLCopy(AHeader.ArcName, PWideChar(FFileName), High(AHeader.ArcName));

	// Copy file path (use backslash for TC)
	LPath := LEntry.Path;
	StrLCopy(AHeader.FileName, PWideChar(LPath), High(AHeader.FileName));

	// File size (split into low/high 32-bit parts)
	AHeader.UnpSize := Cardinal(LEntry.UnpackedSize and $FFFFFFFF);
	AHeader.UnpSizeHigh := Cardinal(LEntry.UnpackedSize shr 32);
	AHeader.PackSize := AHeader.UnpSize;
	AHeader.PackSizeHigh := AHeader.UnpSizeHigh;

	// Timestamp
	AHeader.FileTime := LEntry.FileTime;

	// Attributes
	if LEntry.Kind = vfResourceDir then
		AHeader.FileAttr := faDirectory
	else
		AHeader.FileAttr := $20; // FILE_ATTRIBUTE_ARCHIVE

	Result := 0;
end;

function TGeminiArchive.ProcessCurrentFile(AOperation: Integer; const ADestPath, ADestName: string): Integer;
var
	LEntry: TVirtualFileEntry;
	LFullPath: string;
begin
	if FCurrentIndex >= FVirtualFiles.Count then
		Exit(E_END_ARCHIVE);

	LEntry := FVirtualFiles[FCurrentIndex];
	Inc(FCurrentIndex);

	if AOperation = PK_SKIP then
		Exit(0);

	// Determine output path
	if ADestName <> '' then
		LFullPath := ADestName
	else if ADestPath <> '' then
		LFullPath := TPath.Combine(ADestPath, LEntry.Path)
	else
		Exit(E_ECREATE);

	if AOperation = PK_TEST then
		Exit(0);

	// PK_EXTRACT
	Result := ExtractVirtualFile(LEntry, LFullPath);
end;

function TGeminiArchive.ExtractVirtualFile(const AEntry: TVirtualFileEntry; const ADestPath: string): Integer;
var
	LDir: string;
	LFmt: IGeminiFormatter;
	LConfig: TPluginConfig;
	I: Integer;
begin
	// Ensure destination directory exists
	LDir := TPath.GetDirectoryName(ADestPath);
	if (LDir <> '') and not TDirectory.Exists(LDir) then
		ForceDirectories(LDir);

	case AEntry.Kind of
		vfConversationText:
			Result := WriteBytesToFile(FCachedText, ADestPath);

		vfConversationMarkdown:
			Result := WriteBytesToFile(FCachedMarkdown, ADestPath);

		vfConversationHtml:
			Result := WriteBytesToFile(FCachedHtml, ADestPath);

		vfConversationHtmlEmbedded:
			begin
				// Load base64 data on demand for embedding
				for I := 0 to High(FResourceInfos) do
					FResourceInfos[I].Base64Data := FResources[I].Base64Data; // triggers lazy load

				// Generate on-demand (can be large)
				LConfig := GetPluginConfig;
				LFmt := TGeminiHtmlFormatter.Create(BuildWcxHtmlConfig(LConfig, True, TPath.GetFileNameWithoutExtension(FFileName), LoadCustomCSS));
				Result := WriteBytesToFile(FormatToBytes(LFmt), ADestPath);

				// Release base64 data to free memory
				for I := 0 to High(FResourceInfos) do
					FResourceInfos[I].Base64Data := '';
				for I := 0 to High(FResources) do
					FResources[I].ReleaseBase64;
			end;

		vfResourceDir:
			begin
				// Create the directory
				if not TDirectory.Exists(ADestPath) then
					ForceDirectories(ADestPath);
				Result := 0;
			end;

		vfResource:
			begin
				if (AEntry.ResourceIndex < 0) or (AEntry.ResourceIndex > High(FResources)) then
					Exit(E_BAD_DATA);
				try
					FResources[AEntry.ResourceIndex].SaveToFile(ADestPath);
					ReportProgress(ADestPath, FResources[AEntry.ResourceIndex].DecodedSize);
					Result := 0;
				except
					Result := E_EWRITE;
				end;
			end;
		else
			Result := E_NOT_SUPPORTED;
	end;
end;

function TGeminiArchive.WriteBytesToFile(const AData: TBytes; const AFilePath: string): Integer;
var
	LFileStream: TFileStream;
begin
	try
		LFileStream := TFileStream.Create(AFilePath, fmCreate);
		try
			if Length(AData) > 0 then
				LFileStream.WriteBuffer(AData[0], Length(AData));
			ReportProgress(AFilePath, Length(AData));
		finally
			LFileStream.Free;
		end;
		Result := 0;
	except
		Result := E_ECREATE;
	end;
end;

procedure TGeminiArchive.ReportProgress(const AFileName: string; ASize: Integer);
begin
	if Assigned(FProcessDataProc) then
		FProcessDataProc(PWideChar(AFileName), ASize);
end;

// ========================================================================
// Exported functions -- Unicode (primary)
// ========================================================================

function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;
var
	LArchive: TGeminiArchive;
begin
	Result := 0;
	try
		LArchive := TGeminiArchive.Create(ArchiveData.ArcName, ArchiveData.OpenMode);
		GArchives.Add(LArchive);
		ArchiveData.OpenResult := 0;
		Result := THandle(LArchive);
	except
		on E: EFileNotFoundException do
			ArchiveData.OpenResult := E_EOPEN;
		on E: EGeminiParseError do
			ArchiveData.OpenResult := E_BAD_ARCHIVE;
		on E: Exception do
			ArchiveData.OpenResult := E_BAD_DATA;
	end;
end;

function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;
begin
	if not IsValidHandle(hArcData) then
		Exit(E_BAD_ARCHIVE);
	Result := TGeminiArchive(hArcData).ReadNextHeader(HeaderData);
end;

function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath: PWideChar; DestName: PWideChar): Integer; stdcall;
var
	LDestPath, LDestName: string;
begin
	if not IsValidHandle(hArcData) then
		Exit(E_BAD_ARCHIVE);

	if DestPath <> nil then
		LDestPath := DestPath
	else
		LDestPath := '';

	if DestName <> nil then
		LDestName := DestName
	else
		LDestName := '';

	Result := TGeminiArchive(hArcData).ProcessCurrentFile(Operation, LDestPath, LDestName);
end;

function CloseArchive(hArcData: THandle): Integer; stdcall;
var
	LArchive: TGeminiArchive;
begin
	if not IsValidHandle(hArcData) then
		Exit(E_BAD_ARCHIVE);
	LArchive := TGeminiArchive(hArcData);
	GArchives.Remove(LArchive);
	LArchive.Free;
	Result := 0;
end;

procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
begin
	if IsValidHandle(hArcData) then
		TGeminiArchive(hArcData).ChangeVolProc := pChangeVolProc;
end;

procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;
begin
	if IsValidHandle(hArcData) then
		TGeminiArchive(hArcData).ProcessDataProc := pProcessDataProc;
end;

function GetPackerCaps: Integer; stdcall;
begin
	Result := PK_CAPS_MULTIPLE or PK_CAPS_BY_CONTENT or PK_CAPS_SEARCHTEXT;
end;

function CanYouHandleThisFileW(FileName: PWideChar): LongBool; stdcall;
const
	/// Read enough to find "runSettings" even when preceded by large whitespace or BOM
	SNIFF_SIZE = 8192;
	MARKER: UTF8String = 'runSettings';
var
	LStream: TFileStream;
	LBuf: TBytes;
	LBytesRead: Integer;
	LByte: Byte;
	LBom: array [0 .. 1] of Byte;
	LFoundBrace: Boolean;
	I, J: Integer;
	LMarkerLen: Integer;
begin
	Result := False;
	try
		LStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
		try
			// Skip UTF-8 BOM if present (EF BB BF)
			if (LStream.Size >= 3) and (LStream.Read(LByte, 1) = 1) and (LByte = $EF) then
			begin
				if (LStream.Read(LBom, 2) = 2) and (LBom[0] = $BB) and (LBom[1] = $BF) then
					{BOM consumed, stream at position 3}
				else
					LStream.Position := 0;
			end
			else
				LStream.Position := 0;

			// Skip whitespace, look for '{'
			LFoundBrace := False;
			while LStream.Read(LByte, 1) = 1 do
			begin
				if LByte in [$09, $0A, $0D, $20] then
					Continue;
				LFoundBrace := LByte = Ord('{');
				Break;
			end;

			if not LFoundBrace then
				Exit;

			// Read first SNIFF_SIZE bytes and look for "runSettings" marker
			LStream.Position := 0;
			SetLength(LBuf, SNIFF_SIZE);
			LBytesRead := LStream.Read(LBuf[0], SNIFF_SIZE);
			if LBytesRead <= 0 then
				Exit;

			LMarkerLen := Length(MARKER);
			for I := 0 to LBytesRead - LMarkerLen do
			begin
				J := 0;
				while (J < LMarkerLen) and (LBuf[I + J] = Ord(MARKER[J + 1])) do
					Inc(J);
				if J = LMarkerLen then
				begin
					Result := True;
					Exit;
				end;
			end;
		finally
			LStream.Free;
		end;
	except
		Result := False;
	end;
end;

function GetBackgroundFlags: Integer; stdcall;
begin
	Result := BACKGROUND_UNPACK;
end;

// ========================================================================
// Exported functions -- ANSI (compatibility)
// ========================================================================

function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
var
	LDataW: TOpenArchiveDataW;
	LArcNameW: WideString;
begin
	FillChar(LDataW, SizeOf(LDataW), 0);
	LArcNameW := WideString(AnsiString(ArchiveData.ArcName));
	LDataW.ArcName := PWideChar(LArcNameW);
	LDataW.OpenMode := ArchiveData.OpenMode;

	Result := OpenArchiveW(LDataW);

	ArchiveData.OpenResult := LDataW.OpenResult;
end;

function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
var
	LHeaderW: THeaderDataExW;
	LAnsi: AnsiString;
begin
	Result := ReadHeaderExW(hArcData, LHeaderW);
	if Result <> 0 then
		Exit;

	FillChar(HeaderData, SizeOf(HeaderData), 0);

	LAnsi := AnsiString(WideString(LHeaderW.ArcName));
	System.AnsiStrings.StrLCopy(HeaderData.ArcName, PAnsiChar(LAnsi), High(HeaderData.ArcName));

	LAnsi := AnsiString(WideString(LHeaderW.FileName));
	System.AnsiStrings.StrLCopy(HeaderData.FileName, PAnsiChar(LAnsi), High(HeaderData.FileName));

	HeaderData.PackSize := Integer(LHeaderW.PackSize);
	HeaderData.UnpSize := Integer(LHeaderW.UnpSize);
	HeaderData.FileTime := LHeaderW.FileTime;
	HeaderData.FileAttr := LHeaderW.FileAttr;
	HeaderData.Flags := LHeaderW.Flags;
end;

function ReadHeaderEx(hArcData: THandle; var HeaderData: THeaderDataEx): Integer; stdcall;
var
	LHeaderW: THeaderDataExW;
	LAnsi: AnsiString;
begin
	Result := ReadHeaderExW(hArcData, LHeaderW);
	if Result <> 0 then
		Exit;

	FillChar(HeaderData, SizeOf(HeaderData), 0);

	LAnsi := AnsiString(WideString(LHeaderW.ArcName));
	System.AnsiStrings.StrLCopy(HeaderData.ArcName, PAnsiChar(LAnsi), High(HeaderData.ArcName));

	LAnsi := AnsiString(WideString(LHeaderW.FileName));
	System.AnsiStrings.StrLCopy(HeaderData.FileName, PAnsiChar(LAnsi), High(HeaderData.FileName));

	HeaderData.PackSize := LHeaderW.PackSize;
	HeaderData.PackSizeHigh := LHeaderW.PackSizeHigh;
	HeaderData.UnpSize := LHeaderW.UnpSize;
	HeaderData.UnpSizeHigh := LHeaderW.UnpSizeHigh;
	HeaderData.FileTime := LHeaderW.FileTime;
	HeaderData.FileAttr := LHeaderW.FileAttr;
	HeaderData.Flags := LHeaderW.Flags;
end;

function ProcessFile(hArcData: THandle; Operation: Integer; DestPath: PAnsiChar; DestName: PAnsiChar): Integer; stdcall;
var
	LDestPathW, LDestNameW: PWideChar;
	LPathStr, LNameStr: WideString;
begin
	LDestPathW := nil;
	LDestNameW := nil;

	if DestPath <> nil then
	begin
		LPathStr := WideString(AnsiString(DestPath));
		LDestPathW := PWideChar(LPathStr);
	end;

	if DestName <> nil then
	begin
		LNameStr := WideString(AnsiString(DestName));
		LDestNameW := PWideChar(LNameStr);
	end;

	Result := ProcessFileW(hArcData, Operation, LDestPathW, LDestNameW);
end;

procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
begin
	// ANSI callback not stored -- TC uses Unicode variant when available
end;

procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
begin
	// ANSI callback not stored -- TC uses Unicode variant when available
end;

function CanYouHandleThisFile(FileName: PAnsiChar): LongBool; stdcall;
var
	LWide: WideString;
begin
	LWide := WideString(AnsiString(FileName));
	Result := CanYouHandleThisFileW(PWideChar(LWide));
end;

initialization

GArchives := TThreadList<TGeminiArchive>.Create;

finalization

// Free any leaked archive handles
var LList := GArchives.LockList;
try
	while LList.Count > 0 do
	begin
		LList[0].Free;
		LList.Delete(0);
	end;
finally
	GArchives.UnlockList;
end;
GArchives.Free;

end.
