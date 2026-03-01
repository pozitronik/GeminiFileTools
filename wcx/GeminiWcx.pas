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
	GeminiFile.Formatter.Text,
	GeminiFile.Formatter.Md,
	GeminiFile.Formatter.Html;

type
	TVirtualFileKind = (
		vfConversationText,
		vfConversationMarkdown,
		vfConversationHtml,
		vfConversationHtmlEmbedded,
		vfResourceDir,
		vfResource
	);

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
		procedure BuildVirtualFileList;
		procedure BuildResourceInfos;
		procedure CacheFormattedContent;
		function EstimateEmbeddedHtmlSize: Int64;
		function ExtractVirtualFile(const AEntry: TVirtualFileEntry;
			const ADestPath: string): Integer;
		function WriteStreamToFile(AStream: TStream; const AFilePath: string): Integer;
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
		function ProcessCurrentFile(AOperation: Integer;
			const ADestPath, ADestName: string): Integer;

		property ProcessDataProc: TProcessDataProcW write FProcessDataProc;
		property ChangeVolProc: TChangeVolProcW write FChangeVolProc;
	end;

	TPluginConfig = record
		UseOriginalName: Boolean;
		HideEmptyBlocksText: Boolean;
		HideEmptyBlocksMd: Boolean;
		HideEmptyBlocksHtml: Boolean;
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
function ProcessFileW(hArcData: THandle; Operation: Integer;
	DestPath: PWideChar; DestName: PWideChar): Integer; stdcall;
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
function ProcessFile(hArcData: THandle; Operation: Integer;
	DestPath: PAnsiChar; DestName: PAnsiChar): Integer; stdcall;
procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
function CanYouHandleThisFile(FileName: PAnsiChar): LongBool; stdcall;

implementation

var
	/// Tracks live archive handles for validation
	GArchives: TList<TGeminiArchive>;
	/// Cached custom CSS from gemini.css next to the DLL
	GCustomCSS: string;
	GCustomCSSLoaded: Boolean;
	/// Cached plugin configuration from gemini.ini
	GPluginConfig: TPluginConfig;
	GPluginConfigLoaded: Boolean;

/// <summary>
///   Returns custom CSS content from gemini.css located next to the plugin DLL.
///   Caches the result on first call; returns empty string if file not found.
/// </summary>
function GetCustomCSS: string;
var
	LDllPath: array[0..MAX_PATH] of Char;
	LCssPath: string;
begin
	if not GCustomCSSLoaded then
	begin
		GCustomCSSLoaded := True;
		GCustomCSS := '';
		if GetModuleFileName(HInstance, LDllPath, MAX_PATH + 1) > 0 then
		begin
			LCssPath := TPath.Combine(TPath.GetDirectoryName(LDllPath), 'gemini.css');
			if TFile.Exists(LCssPath) then
				GCustomCSS := TFile.ReadAllText(LCssPath, TEncoding.UTF8);
		end;
	end;
	Result := GCustomCSS;
end;

function GetPluginConfig: TPluginConfig;
var
	LDllPath: array[0..MAX_PATH] of Char;
	LIniPath: string;
	LIni: TIniFile;
begin
	if not GPluginConfigLoaded then
	begin
		GPluginConfigLoaded := True;
		// Defaults (record Default zeroes booleans, so set True defaults explicitly)
		GPluginConfig := Default(TPluginConfig);
		GPluginConfig.HideEmptyBlocksText := True;
		GPluginConfig.HideEmptyBlocksMd := True;
		GPluginConfig.HideEmptyBlocksHtml := True;
		if GetModuleFileName(HInstance, LDllPath, MAX_PATH + 1) > 0 then
		begin
			LIniPath := TPath.Combine(TPath.GetDirectoryName(LDllPath), 'gemini.ini');
			if TFile.Exists(LIniPath) then
			begin
				LIni := TIniFile.Create(LIniPath);
				try
					GPluginConfig.UseOriginalName :=
						LIni.ReadBool('General', 'UseOriginalName', False);
					GPluginConfig.HideEmptyBlocksText :=
						LIni.ReadBool('Formatters', 'HideEmptyBlocksText', True);
					GPluginConfig.HideEmptyBlocksMd :=
						LIni.ReadBool('Formatters', 'HideEmptyBlocksMd', True);
					GPluginConfig.HideEmptyBlocksHtml :=
						LIni.ReadBool('Formatters', 'HideEmptyBlocksHtml', True);
				finally
					LIni.Free;
				end;
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
begin
	Result := (hArcData <> 0) and GArchives.Contains(TGeminiArchive(hArcData));
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

{ TGeminiArchive }

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
	BuildResourceInfos;
	CacheFormattedContent;
	BuildVirtualFileList;
end;

destructor TGeminiArchive.Destroy;
begin
	FreeAndNil(FVirtualFiles);
	FreeAndNil(FGeminiFile);
	inherited;
end;

procedure TGeminiArchive.BuildResourceInfos;
var
	I: Integer;
	LPadWidth: Integer;
begin
	SetLength(FResourceInfos, Length(FResources));
	LPadWidth := Length(IntToStr(Length(FResources)));
	if LPadWidth < 3 then
		LPadWidth := 3;

	for I := 0 to High(FResources) do
	begin
		FResourceInfos[I].FileName := Format('resources/resource_%.*d%s',
			[LPadWidth, I, FResources[I].GetFileExtension]);
		FResourceInfos[I].MimeType := FResources[I].MimeType;
		FResourceInfos[I].Base64Data := FResources[I].Base64Data;
		FResourceInfos[I].DecodedSize := FResources[I].DecodedSize;
		FResourceInfos[I].ChunkIndex := FResources[I].ChunkIndex;
	end;
end;

procedure TGeminiArchive.CacheFormattedContent;
var
	LStream: TMemoryStream;
	LFormatter: TGeminiTextFormatter;
	LMdFormatter: TGeminiMarkdownFormatter;
	LHtmlFormatter: TGeminiHtmlFormatter;
	LConfig: TPluginConfig;
begin
	LConfig := GetPluginConfig;

	// Plain text
	LStream := TMemoryStream.Create;
	try
		LFormatter := TGeminiTextFormatter.Create;
		try
			LFormatter.HideEmptyBlocks := LConfig.HideEmptyBlocksText;
			LFormatter.FormatToStream(LStream, FGeminiFile.Chunks,
				FGeminiFile.SystemInstruction, FGeminiFile.RunSettings, FResourceInfos);
		finally
			LFormatter.Free;
		end;
		SetLength(FCachedText, LStream.Size);
		if LStream.Size > 0 then
		begin
			LStream.Position := 0;
			LStream.ReadBuffer(FCachedText[0], LStream.Size);
		end;
	finally
		LStream.Free;
	end;

	// Markdown
	LStream := TMemoryStream.Create;
	try
		LMdFormatter := TGeminiMarkdownFormatter.Create;
		try
			LMdFormatter.HideEmptyBlocks := LConfig.HideEmptyBlocksMd;
			LMdFormatter.FormatToStream(LStream, FGeminiFile.Chunks,
				FGeminiFile.SystemInstruction, FGeminiFile.RunSettings, FResourceInfos);
		finally
			LMdFormatter.Free;
		end;
		SetLength(FCachedMarkdown, LStream.Size);
		if LStream.Size > 0 then
		begin
			LStream.Position := 0;
			LStream.ReadBuffer(FCachedMarkdown[0], LStream.Size);
		end;
	finally
		LStream.Free;
	end;

	// HTML (external resources)
	LStream := TMemoryStream.Create;
	try
		LHtmlFormatter := TGeminiHtmlFormatter.Create(False, GetCustomCSS);
		try
			LHtmlFormatter.HideEmptyBlocks := LConfig.HideEmptyBlocksHtml;
			LHtmlFormatter.FormatToStream(LStream, FGeminiFile.Chunks,
				FGeminiFile.SystemInstruction, FGeminiFile.RunSettings, FResourceInfos);
		finally
			LHtmlFormatter.Free;
		end;
		SetLength(FCachedHtml, LStream.Size);
		if LStream.Size > 0 then
		begin
			LStream.Position := 0;
			LStream.ReadBuffer(FCachedHtml[0], LStream.Size);
		end;
	finally
		LStream.Free;
	end;
end;

function TGeminiArchive.EstimateEmbeddedHtmlSize: Int64;
var
	I: Integer;
begin
	Result := Length(FCachedHtml);
	for I := 0 to High(FResourceInfos) do
		Inc(Result, Length(FResourceInfos[I].Base64Data) + 100);
end;

procedure TGeminiArchive.BuildVirtualFileList;
var
	LEntry: TVirtualFileEntry;
	I: Integer;
	LPadWidth: Integer;
begin
	FVirtualFiles.Clear;

	// conversation.txt (or originalname.txt)
	LEntry := Default(TVirtualFileEntry);
	LEntry.Path := FBaseName + '.txt';
	LEntry.Kind := vfConversationText;
	LEntry.UnpackedSize := Length(FCachedText);
	LEntry.FileTime := FFileTime;
	FVirtualFiles.Add(LEntry);

	// conversation.md (or originalname.md)
	LEntry := Default(TVirtualFileEntry);
	LEntry.Path := FBaseName + '.md';
	LEntry.Kind := vfConversationMarkdown;
	LEntry.UnpackedSize := Length(FCachedMarkdown);
	LEntry.FileTime := FFileTime;
	FVirtualFiles.Add(LEntry);

	// conversation.html (or originalname.html)
	LEntry := Default(TVirtualFileEntry);
	LEntry.Path := FBaseName + '.html';
	LEntry.Kind := vfConversationHtml;
	LEntry.UnpackedSize := Length(FCachedHtml);
	LEntry.FileTime := FFileTime;
	FVirtualFiles.Add(LEntry);

	if Length(FResources) > 0 then
	begin
		// conversation_full.html (or originalname_full.html, embedded)
		LEntry := Default(TVirtualFileEntry);
		LEntry.Path := FBaseName + '_full.html';
		LEntry.Kind := vfConversationHtmlEmbedded;
		LEntry.UnpackedSize := EstimateEmbeddedHtmlSize;
		LEntry.FileTime := FFileTime;
		FVirtualFiles.Add(LEntry);

		// resources\ directory
		LEntry := Default(TVirtualFileEntry);
		LEntry.Path := 'resources';
		LEntry.Kind := vfResourceDir;
		LEntry.UnpackedSize := 0;
		LEntry.FileTime := FFileTime;
		FVirtualFiles.Add(LEntry);

		// Individual resources
		LPadWidth := Length(IntToStr(Length(FResources)));
		if LPadWidth < 3 then
			LPadWidth := 3;

		for I := 0 to High(FResources) do
		begin
			LEntry := Default(TVirtualFileEntry);
			LEntry.Path := Format('resources\resource_%.*d%s',
				[LPadWidth, I, FResources[I].GetFileExtension]);
			LEntry.Kind := vfResource;
			LEntry.UnpackedSize := FResources[I].DecodedSize;
			LEntry.FileTime := FFileTime;
			LEntry.ResourceIndex := I;
			FVirtualFiles.Add(LEntry);
		end;
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

function TGeminiArchive.ProcessCurrentFile(AOperation: Integer;
	const ADestPath, ADestName: string): Integer;
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

function TGeminiArchive.ExtractVirtualFile(const AEntry: TVirtualFileEntry;
	const ADestPath: string): Integer;
var
	LDir: string;
	LStream: TMemoryStream;
	LFormatter: TGeminiHtmlFormatter;
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
			// Generate on-demand (can be large)
			LStream := TMemoryStream.Create;
			try
				LFormatter := TGeminiHtmlFormatter.Create(True, GetCustomCSS);
				try
					LFormatter.HideEmptyBlocks := GetPluginConfig.HideEmptyBlocksHtml;
					LFormatter.FormatToStream(LStream, FGeminiFile.Chunks,
						FGeminiFile.SystemInstruction, FGeminiFile.RunSettings,
						FResourceInfos);
				finally
					LFormatter.Free;
				end;
				LStream.Position := 0;
				Result := WriteStreamToFile(LStream, ADestPath);
			finally
				LStream.Free;
			end;
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

function TGeminiArchive.WriteStreamToFile(AStream: TStream; const AFilePath: string): Integer;
var
	LFileStream: TFileStream;
	LBuf: array[0..65535] of Byte;
	LRead: Integer;
begin
	try
		LFileStream := TFileStream.Create(AFilePath, fmCreate);
		try
			repeat
				LRead := AStream.Read(LBuf, SizeOf(LBuf));
				if LRead > 0 then
				begin
					LFileStream.WriteBuffer(LBuf, LRead);
					ReportProgress(AFilePath, LRead);
				end;
			until LRead = 0;
		finally
			LFileStream.Free;
		end;
		Result := 0;
	except
		Result := E_ECREATE;
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

function ProcessFileW(hArcData: THandle; Operation: Integer;
	DestPath: PWideChar; DestName: PWideChar): Integer; stdcall;
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
var
	LStream: TFileStream;
	LByte: Byte;
	LBom: array[0..1] of Byte;
begin
	Result := False;
	try
		LStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
		try
			// Skip UTF-8 BOM if present (EF BB BF)
			if (LStream.Size >= 3) and (LStream.Read(LByte, 1) = 1) and (LByte = $EF) then
			begin
				if (LStream.Read(LBom, 2) = 2) and (LBom[0] = $BB) and (LBom[1] = $BF) then
					{ BOM consumed, stream at position 3 }
				else
					LStream.Position := 0; // Not a BOM, rewind
			end
			else
				LStream.Position := 0;

			// Skip whitespace, look for '{'
			while LStream.Read(LByte, 1) = 1 do
			begin
				if LByte in [$09, $0A, $0D, $20] then
					Continue;
				Result := LByte = Ord('{');
				Break;
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

function ProcessFile(hArcData: THandle; Operation: Integer;
	DestPath: PAnsiChar; DestName: PAnsiChar): Integer; stdcall;
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
	GArchives := TList<TGeminiArchive>.Create;

finalization
	// Free any leaked archive handles
	while GArchives.Count > 0 do
	begin
		GArchives[0].Free;
		GArchives.Delete(0);
	end;
	GArchives.Free;

end.
