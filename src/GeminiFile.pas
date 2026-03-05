/// <summary>
///   Facade unit for the GeminiFile library.
///   Provides backward-compatible API by delegating to parser and extractor.
///   Re-exports all types from sub-units so consumers can use GeminiFile
///   as a single entry point.
/// </summary>
unit GeminiFile;

{$IFDEF FPC}
{$MODE DELPHI}
{$ENDIF}

interface

uses
	System.SysUtils,
	System.Classes,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Parser,
	GeminiFile.Extractor,
	GeminiFile.LazyData;

type
	// Re-export types from sub-units for backward compatibility
	TGeminiRole = GeminiFile.Types.TGeminiRole;
	TGeminiSafetySetting = GeminiFile.Types.TGeminiSafetySetting;
	TGeminiSafetyRating = GeminiFile.Types.TGeminiSafetyRating;
	TGeminiExtractProgressEvent = GeminiFile.Types.TGeminiExtractProgressEvent;
	EGeminiParseError = GeminiFile.Types.EGeminiParseError;

	TGeminiResource = GeminiFile.Model.TGeminiResource;
	TGeminiPart = GeminiFile.Model.TGeminiPart;
	TGeminiChunk = GeminiFile.Model.TGeminiChunk;
	TGeminiRunSettings = GeminiFile.Model.TGeminiRunSettings;

	IGeminiFileParser = GeminiFile.Parser.IGeminiFileParser;
	IGeminiResourceExtractor = GeminiFile.Extractor.IGeminiResourceExtractor;

/// <summary>
///   Builds a TFormatterResourceInfo array from resources and chunks.
///   Thinking resources get a 'resources/think/' subdirectory prefix;
///   normal resources get 'resources/'. Base64Data is left empty (loaded on demand).
///   Shared by WCX and WLX plugins to avoid duplicated logic.
/// </summary>
/// <param name="AResources">Flat array of resources from TGeminiFile.GetResources.</param>
/// <param name="AChunks">Chunk list for IsThought lookup.</param>
/// <returns>Array of resource info records ready for formatters.</returns>
function BuildFormatterResourceInfos(
	const AResources: TArray<GeminiFile.Model.TGeminiResource>;
	AChunks: TObjectList<GeminiFile.Model.TGeminiChunk>): TArray<GeminiFile.Types.TFormatterResourceInfo>;

type
	/// <summary>
	///   Top-level container for a Gemini conversation file.
	///   Thin facade delegating to parser and extractor.
	///   Entry point for parsing, reading, and extracting resources.
	/// </summary>
	TGeminiFile = class
	private
		FRunSettings: GeminiFile.Model.TGeminiRunSettings;
		FSystemInstruction: string;
		FChunks: TObjectList<GeminiFile.Model.TGeminiChunk>;
		FOnExtractProgress: GeminiFile.Types.TGeminiExtractProgressEvent;
		FParser: IGeminiFileParser;
		FExtractor: IGeminiResourceExtractor;
		FFilePath: string;
		FCachedResources: TArray<GeminiFile.Model.TGeminiResource>;
		FResourcesCached: Boolean;
		/// <summary>
		///   Walks all chunks/parts, replacing placeholder resources with lazy variants.
		/// </summary>
		procedure LinkLazyResources(const ALocations: TArray<TBase64Location>);
		/// <summary>
		///   Checks if a resource holds a __LAZY:N placeholder and returns a lazy replacement.
		///   Returns nil if the resource is not a placeholder.
		/// </summary>
		function ConvertToLazyIfNeeded(AResource: GeminiFile.Model.TGeminiResource; const ALocations: TArray<TBase64Location>): GeminiFile.Model.TGeminiResource;
		/// <summary>Populates FCachedResources if not already cached.</summary>
		procedure EnsureResourcesCached;
	public
		/// <summary>
		///   Creates a TGeminiFile with default parser and extractor implementations.
		/// </summary>
		constructor Create; overload;
		/// <summary>
		///   Creates a TGeminiFile with injected parser and extractor (DIP).
		/// </summary>
		/// <param name="AParser">Parser implementation to use.</param>
		/// <param name="AExtractor">Extractor implementation to use.</param>
		constructor Create(const AParser: IGeminiFileParser; const AExtractor: IGeminiResourceExtractor); overload;
		destructor Destroy; override;

		/// <summary>
		///   Loads and parses a Gemini conversation file.
		/// </summary>
		/// <param name="AFileName">Full path to the Gemini file.</param>
		/// <exception cref="EFileNotFoundException">If the file does not exist.</exception>
		/// <exception cref="EGeminiParseError">If the file contains invalid JSON.</exception>
		procedure LoadFromFile(const AFileName: string);

		/// <summary>
		///   Loads and parses a Gemini conversation from a stream.
		/// </summary>
		/// <param name="AStream">Stream containing UTF-8 encoded JSON.</param>
		/// <exception cref="EGeminiParseError">If the stream contains invalid JSON.</exception>
		procedure LoadFromStream(AStream: TStream);

		/// <summary>
		///   Returns a flat array of all embedded resources (deduplicated).
		///   Checks InlineImage at chunk level first, falls back to parts.
		/// </summary>
		/// <returns>Array of TGeminiResource references. Caller must NOT free these.</returns>
		function GetResources: TArray<GeminiFile.Model.TGeminiResource>;

		/// <summary>Returns the count of embedded resources.</summary>
		function GetResourceCount: Integer;

		/// <summary>
		///   Extracts all embedded resources to files in the specified directory.
		///   Files are named resource_NNN.ext where NNN is a zero-padded index.
		/// </summary>
		/// <param name="AOutputDir">Directory to write files to. Created if it does not exist.</param>
		/// <param name="AThreaded">If True, uses parallel extraction. Default True.</param>
		/// <param name="ANamePrefix">Optional filename prefix. Default 'resource'.</param>
		/// <returns>Number of resources extracted.</returns>
		function ExtractAllResources(const AOutputDir: string; AThreaded: Boolean = True; const ANamePrefix: string = 'resource'): Integer;

		/// <summary>Total number of chunks in the conversation.</summary>
		function ChunkCount: Integer;
		/// <summary>Number of user message chunks.</summary>
		function UserChunkCount: Integer;
		/// <summary>Number of model response chunks (including thought chunks).</summary>
		function ModelChunkCount: Integer;
		/// <summary>Sum of all TokenCount values across chunks.</summary>
		function TotalTokenCount: Integer;

		/// <summary>Model run settings (temperature, model, etc.).</summary>
		property RunSettings: GeminiFile.Model.TGeminiRunSettings read FRunSettings;
		/// <summary>System instruction text. Empty if not provided.</summary>
		property SystemInstruction: string read FSystemInstruction;
		/// <summary>All conversation chunks in order.</summary>
		property Chunks: TObjectList<GeminiFile.Model.TGeminiChunk> read FChunks;
		/// <summary>Event fired during extraction to report progress.</summary>
		property OnExtractProgress: GeminiFile.Types.TGeminiExtractProgressEvent read FOnExtractProgress write FOnExtractProgress;
	end;

implementation

{TGeminiFile}

constructor TGeminiFile.Create;
begin
	Create(TGeminiFileParser.Create, TGeminiResourceExtractor.Create);
end;

constructor TGeminiFile.Create(const AParser: IGeminiFileParser; const AExtractor: IGeminiResourceExtractor);
begin
	inherited Create;
	FRunSettings := GeminiFile.Model.TGeminiRunSettings.Create;
	FChunks := TObjectList<GeminiFile.Model.TGeminiChunk>.Create(True);
	FParser := AParser;
	FExtractor := AExtractor;
end;

destructor TGeminiFile.Destroy;
begin
	FreeAndNil(FChunks);
	FreeAndNil(FRunSettings);
	inherited;
end;

procedure TGeminiFile.LoadFromFile(const AFileName: string);
var
	LFileStream: TFileStream;
	LBytes: TBytes;
	LScanResult: TPreScanResult;
	LBytesStream: TBytesStream;
begin
	if not FileExists(AFileName) then
		raise EFileNotFoundException.CreateFmt('File not found: %s', [AFileName]);
	FFilePath := AFileName;
	FResourcesCached := False;

	// Read raw bytes
	LFileStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
	try
		SetLength(LBytes, LFileStream.Size);
		if LFileStream.Size > 0 then
			LFileStream.ReadBuffer(LBytes[0], LFileStream.Size);
	finally
		LFileStream.Free;
	end;

	// Pre-scan: strip large base64 values, record their byte locations
	LScanResult := PreScanGeminiFile(LBytes);
	SetLength(LBytes, 0); // free raw bytes early

	// Parse stripped JSON bytes directly (no string conversion round-trip)
	LBytesStream := TBytesStream.Create(LScanResult.StrippedJsonBytes);
	try
		FSystemInstruction := FParser.Parse(LBytesStream, FRunSettings, FChunks);
	finally
		LBytesStream.Free;
	end;

	// Post-process: convert placeholder resources to lazy-loading variants
	if Length(LScanResult.Locations) > 0 then
		LinkLazyResources(LScanResult.Locations);
end;

procedure TGeminiFile.LoadFromStream(AStream: TStream);
begin
	FFilePath := '';
	FResourcesCached := False;
	FSystemInstruction := FParser.Parse(AStream, FRunSettings, FChunks);
end;

function TGeminiFile.ConvertToLazyIfNeeded(AResource: GeminiFile.Model.TGeminiResource; const ALocations: TArray<TBase64Location>): GeminiFile.Model.TGeminiResource;
var
	LIndex: Integer;
begin
	Result := nil;
	LIndex := AResource.GetLazyPlaceholderIndex;
	if (LIndex < 0) or (LIndex > High(ALocations)) then
		Exit;

	Result := GeminiFile.Model.TGeminiResource.CreateLazy(AResource.MimeType, AResource.ChunkIndex, FFilePath, ALocations[LIndex]);
end;

procedure TGeminiFile.LinkLazyResources(const ALocations: TArray<TBase64Location>);
var
	LChunk: GeminiFile.Model.TGeminiChunk;
	LPart: GeminiFile.Model.TGeminiPart;
	LLazy: GeminiFile.Model.TGeminiResource;
begin
	for LChunk in FChunks do
	begin
		// Check chunk-level InlineImage
		if LChunk.InlineImage <> nil then
		begin
			LLazy := ConvertToLazyIfNeeded(LChunk.InlineImage, ALocations);
			if LLazy <> nil then
			begin
				LChunk.InlineImage.Free;
				LChunk.InlineImage := LLazy;
			end;
		end;

		// Check parts
		for LPart in LChunk.Parts do
		begin
			if LPart.InlineData <> nil then
			begin
				LLazy := ConvertToLazyIfNeeded(LPart.InlineData, ALocations);
				if LLazy <> nil then
				begin
					LPart.InlineData.Free;
					LPart.InlineData := LLazy;
				end;
			end;
		end;
	end;
end;

procedure TGeminiFile.EnsureResourcesCached;
var
	LList: TList<GeminiFile.Model.TGeminiResource>;
	LChunk: GeminiFile.Model.TGeminiChunk;
	LRes: GeminiFile.Model.TGeminiResource;
begin
	if FResourcesCached then
		Exit;
	LList := TList<GeminiFile.Model.TGeminiResource>.Create;
	try
		for LChunk in FChunks do
			if LChunk.TryGetResource(LRes) then
				LList.Add(LRes);
		FCachedResources := LList.ToArray;
	finally
		LList.Free;
	end;
	FResourcesCached := True;
end;

function TGeminiFile.GetResources: TArray<GeminiFile.Model.TGeminiResource>;
begin
	EnsureResourcesCached;
	Result := FCachedResources;
end;

function TGeminiFile.GetResourceCount: Integer;
begin
	EnsureResourcesCached;
	Result := Length(FCachedResources);
end;

function TGeminiFile.ExtractAllResources(const AOutputDir: string; AThreaded: Boolean; const ANamePrefix: string): Integer;
begin
	Result := FExtractor.ExtractAll(GetResources, AOutputDir, AThreaded, ANamePrefix, FOnExtractProgress);
end;

function TGeminiFile.ChunkCount: Integer;
begin
	Result := FChunks.Count;
end;

function TGeminiFile.UserChunkCount: Integer;
var
	LChunk: GeminiFile.Model.TGeminiChunk;
begin
	Result := 0;
	for LChunk in FChunks do
		if LChunk.Role = grUser then
			Inc(Result);
end;

function TGeminiFile.ModelChunkCount: Integer;
var
	LChunk: GeminiFile.Model.TGeminiChunk;
begin
	Result := 0;
	for LChunk in FChunks do
		if LChunk.Role = grModel then
			Inc(Result);
end;

function TGeminiFile.TotalTokenCount: Integer;
var
	LChunk: GeminiFile.Model.TGeminiChunk;
begin
	Result := 0;
	for LChunk in FChunks do
		Inc(Result, LChunk.TokenCount);
end;

function BuildFormatterResourceInfos(
	const AResources: TArray<GeminiFile.Model.TGeminiResource>;
	AChunks: TObjectList<GeminiFile.Model.TGeminiChunk>): TArray<GeminiFile.Types.TFormatterResourceInfo>;
var
	I, LPadWidth: Integer;
	LIsThinking: Boolean;
	LSubDir: string;
begin
	SetLength(Result, Length(AResources));
	LPadWidth := ResourcePadWidth(Length(AResources));

	for I := 0 to High(AResources) do
	begin
		LIsThinking := (AResources[I].ChunkIndex >= 0)
			and (AResources[I].ChunkIndex < AChunks.Count)
			and AChunks[AResources[I].ChunkIndex].IsThought;

		if LIsThinking then
			LSubDir := 'resources/think/'
		else
			LSubDir := 'resources/';

		Result[I].FileName := Format(LSubDir + 'resource_%.*d%s',
			[LPadWidth, I, AResources[I].GetFileExtension]);
		Result[I].MimeType := AResources[I].MimeType;
		Result[I].Base64Data := '';
		Result[I].DecodedSize := AResources[I].DecodedSize;
		Result[I].ChunkIndex := AResources[I].ChunkIndex;
		Result[I].IsThinking := LIsThinking;
	end;
end;

end.
