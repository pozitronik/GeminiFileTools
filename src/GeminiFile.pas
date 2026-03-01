/// <summary>
///   Core unit for parsing Google Gemini AI Studio conversation files.
///   These are extensionless JSON files containing conversation text, model settings,
///   thinking traces, and embedded binary resources (images as base64).
///
///   Framework-independent (no VCL/FMX) -- suitable for console apps, DLLs, and plugins.
/// </summary>
unit GeminiFile;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.NetEncoding,
  System.DateUtils,
  System.Generics.Collections,
  System.Threading,
  System.IOUtils,
  System.Math;

type
  /// <summary>Role of a conversation participant.</summary>
  TGeminiRole = (grUser, grModel);

  /// <summary>Safety setting: category + threshold pair from runSettings.</summary>
  TGeminiSafetySetting = record
    Category: string;
    Threshold: string;
  end;

  /// <summary>Safety rating: category + probability pair from model responses.</summary>
  TGeminiSafetyRating = record
    Category: string;
    Probability: string;
  end;

  /// <summary>
  ///   Represents an embedded binary resource (typically an image).
  ///   Supports lazy base64 decoding and memory release after extraction.
  /// </summary>
  TGeminiResource = class
  private
    FMimeType: string;
    FBase64Data: string;
    FDecodedData: TBytes;
    FIsDecoded: Boolean;
    FChunkIndex: Integer;
    function GetDecodedSize: Int64;
    function GetBase64Size: Int64;
  public
    /// <summary>Creates a resource from mime type and base64-encoded data string.</summary>
    /// <param name="AMimeType">MIME type, e.g. 'image/jpeg'.</param>
    /// <param name="ABase64Data">Raw base64-encoded string.</param>
    /// <param name="AChunkIndex">Index of the parent chunk in the conversation.</param>
    constructor Create(const AMimeType, ABase64Data: string; AChunkIndex: Integer);
    destructor Destroy; override;

    /// <summary>
    ///   Decodes base64 data into FDecodedData bytes.
    ///   Clears FBase64Data afterwards to free memory.
    /// </summary>
    /// <exception cref="EEncodingError">If base64 data is malformed.</exception>
    procedure Decode;

    /// <summary>
    ///   Saves the resource to a file. Decodes on demand if not yet decoded.
    /// </summary>
    /// <param name="AFileName">Full path for the output file.</param>
    /// <exception cref="EFCreateError">If the file cannot be created.</exception>
    procedure SaveToFile(const AFileName: string);

    /// <summary>
    ///   Writes decoded data to a stream. Decodes on demand if not yet decoded.
    /// </summary>
    /// <param name="AStream">Target stream.</param>
    procedure SaveToStream(AStream: TStream);

    /// <summary>
    ///   Returns a file extension (with leading dot) based on the MIME type.
    ///   Falls back to '.bin' for unknown types.
    /// </summary>
    /// <returns>File extension string, e.g. '.jpg', '.png'.</returns>
    function GetFileExtension: string;

    /// <summary>Releases the raw base64 string to free memory. Decoded data is kept.</summary>
    procedure ReleaseBase64;

    /// <summary>Releases both base64 and decoded data to free all memory.</summary>
    procedure ReleaseAll;

    /// <summary>MIME type of the resource, e.g. 'image/jpeg'.</summary>
    property MimeType: string read FMimeType;
    /// <summary>Whether the base64 data has been decoded to binary.</summary>
    property IsDecoded: Boolean read FIsDecoded;
    /// <summary>Decoded binary size in bytes. If not yet decoded, estimates from base64 length.</summary>
    property DecodedSize: Int64 read GetDecodedSize;
    /// <summary>Raw base64 string size in characters.</summary>
    property Base64Size: Int64 read GetBase64Size;
    /// <summary>Index of the parent chunk in the conversation.</summary>
    property ChunkIndex: Integer read FChunkIndex;
  end;

  /// <summary>
  ///   One fragment within a model response.
  ///   Model responses are streamed in parts; each part may contain text,
  ///   a thinking fragment, or inline binary data.
  /// </summary>
  TGeminiPart = class
  private
    FText: string;
    FIsThought: Boolean;
    FInlineData: TGeminiResource;
    FThoughtSignature: string;
  public
    destructor Destroy; override;

    /// <summary>Text content of this part.</summary>
    property Text: string read FText write FText;
    /// <summary>True if this part is a thinking/reasoning fragment.</summary>
    property IsThought: Boolean read FIsThought write FIsThought;
    /// <summary>Embedded resource within this part. Nil if text-only.</summary>
    property InlineData: TGeminiResource read FInlineData write FInlineData;
    /// <summary>Thought signature string (opaque, used by Gemini internally).</summary>
    property ThoughtSignature: string read FThoughtSignature write FThoughtSignature;
  end;

  /// <summary>
  ///   One conversation turn -- a user message or a model response.
  /// </summary>
  TGeminiChunk = class
  private
    FText: string;
    FRole: TGeminiRole;
    FTokenCount: Integer;
    FIsThought: Boolean;
    FThinkingBudget: Integer;
    FFinishReason: string;
    FParts: TObjectList<TGeminiPart>;
    FInlineImage: TGeminiResource;
    FDriveImageId: string;
    FErrorMessage: string;
    FSafetyRatings: TArray<TGeminiSafetyRating>;
    FCreateTime: TDateTime;
    FIsGeneratedUsingApiKey: Boolean;
    FThoughtSignatures: TArray<string>;
    FIndex: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    ///   Returns the full text of this chunk.
    ///   If Parts is non-empty, concatenates all non-thought text parts.
    ///   Otherwise returns the direct Text field.
    /// </summary>
    /// <returns>Concatenated response text.</returns>
    function GetFullText: string;

    /// <summary>
    ///   Returns concatenated text of thinking/reasoning parts only.
    ///   Empty string if no thinking parts exist.
    /// </summary>
    /// <returns>Thinking text.</returns>
    function GetThinkingText: string;

    /// <summary>
    ///   Returns True if this chunk contains an embedded resource
    ///   (either via InlineImage or via parts with InlineData).
    /// </summary>
    function HasResource: Boolean;

    /// <summary>
    ///   Returns the primary embedded resource, or nil.
    ///   Checks InlineImage first, then falls back to the first InlineData in Parts.
    /// </summary>
    function GetResource: TGeminiResource;

    /// <summary>Raw text content of this chunk.</summary>
    property Text: string read FText write FText;
    /// <summary>Role: user or model.</summary>
    property Role: TGeminiRole read FRole write FRole;
    /// <summary>Token count for this chunk. 0 if not provided.</summary>
    property TokenCount: Integer read FTokenCount write FTokenCount;
    /// <summary>True if this is a thinking/reasoning step (model only).</summary>
    property IsThought: Boolean read FIsThought write FIsThought;
    /// <summary>Thinking budget. -1 = unlimited, 0 = not specified.</summary>
    property ThinkingBudget: Integer read FThinkingBudget write FThinkingBudget;
    /// <summary>Finish reason string: 'STOP', 'PROHIBITED_CONTENT', etc. Empty if absent.</summary>
    property FinishReason: string read FFinishReason write FFinishReason;
    /// <summary>Sub-parts of this chunk (streaming fragments, inline data). May be empty.</summary>
    property Parts: TObjectList<TGeminiPart> read FParts;
    /// <summary>Embedded image at chunk level. Nil if absent.</summary>
    property InlineImage: TGeminiResource read FInlineImage write FInlineImage;
    /// <summary>Google Drive image ID reference. Empty if absent.</summary>
    property DriveImageId: string read FDriveImageId write FDriveImageId;
    /// <summary>Error message from the model. Empty if absent.</summary>
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    /// <summary>Safety ratings for this response.</summary>
    property SafetyRatings: TArray<TGeminiSafetyRating> read FSafetyRatings write FSafetyRatings;
    /// <summary>Timestamp of this chunk. 0 if not provided.</summary>
    property CreateTime: TDateTime read FCreateTime write FCreateTime;
    /// <summary>Whether this response was generated using an API key.</summary>
    property IsGeneratedUsingApiKey: Boolean read FIsGeneratedUsingApiKey write FIsGeneratedUsingApiKey;
    /// <summary>Thought signature strings (opaque).</summary>
    property ThoughtSignatures: TArray<string> read FThoughtSignatures write FThoughtSignatures;
    /// <summary>Zero-based index of this chunk in the conversation.</summary>
    property Index: Integer read FIndex write FIndex;
  end;

  /// <summary>
  ///   Model configuration from the runSettings section of a Gemini file.
  /// </summary>
  TGeminiRunSettings = class
  private
    FModel: string;
    FTemperature: Double;
    FTopP: Double;
    FTopK: Integer;
    FMaxOutputTokens: Integer;
    FSafetySettings: TArray<TGeminiSafetySetting>;
    FResponseMimeType: string;
    FResponseModalities: TArray<string>;
    FEnableCodeExecution: Boolean;
    FEnableSearchAsATool: Boolean;
    FEnableBrowseAsATool: Boolean;
    FEnableAutoFunctionResponse: Boolean;
  public
    constructor Create;

    /// <summary>Model identifier, e.g. 'models/gemini-2.5-pro'.</summary>
    property Model: string read FModel write FModel;
    /// <summary>Sampling temperature. NaN if not specified.</summary>
    property Temperature: Double read FTemperature write FTemperature;
    /// <summary>Top-P sampling parameter. NaN if not specified.</summary>
    property TopP: Double read FTopP write FTopP;
    /// <summary>Top-K sampling parameter. -1 if not specified.</summary>
    property TopK: Integer read FTopK write FTopK;
    /// <summary>Maximum output token count. -1 if not specified.</summary>
    property MaxOutputTokens: Integer read FMaxOutputTokens write FMaxOutputTokens;
    /// <summary>Safety filter settings.</summary>
    property SafetySettings: TArray<TGeminiSafetySetting> read FSafetySettings write FSafetySettings;
    /// <summary>Response MIME type, e.g. 'text/plain'. Empty if not specified.</summary>
    property ResponseMimeType: string read FResponseMimeType write FResponseMimeType;
    /// <summary>Response modalities, e.g. ['IMAGE','TEXT']. Empty if not specified.</summary>
    property ResponseModalities: TArray<string> read FResponseModalities write FResponseModalities;
    /// <summary>Whether code execution is enabled.</summary>
    property EnableCodeExecution: Boolean read FEnableCodeExecution write FEnableCodeExecution;
    /// <summary>Whether web search is enabled as a tool.</summary>
    property EnableSearchAsATool: Boolean read FEnableSearchAsATool write FEnableSearchAsATool;
    /// <summary>Whether web browsing is enabled as a tool.</summary>
    property EnableBrowseAsATool: Boolean read FEnableBrowseAsATool write FEnableBrowseAsATool;
    /// <summary>Whether automatic function response is enabled.</summary>
    property EnableAutoFunctionResponse: Boolean read FEnableAutoFunctionResponse write FEnableAutoFunctionResponse;
  end;

  /// <summary>
  ///   Callback invoked during resource extraction to report progress.
  ///   Note: in threaded mode, this may be called from worker threads.
  ///   The consumer is responsible for thread safety if needed.
  /// </summary>
  /// <param name="AIndex">Zero-based index of the resource being extracted.</param>
  /// <param name="ATotal">Total number of resources.</param>
  /// <param name="AFileName">Output file name.</param>
  TGeminiExtractProgressEvent = reference to procedure(AIndex, ATotal: Integer; const AFileName: string);

  /// <summary>
  ///   Top-level container for a Gemini conversation file.
  ///   Entry point for parsing, reading, and extracting resources.
  /// </summary>
  TGeminiFile = class
  private
    FRunSettings: TGeminiRunSettings;
    FSystemInstruction: string;
    FChunks: TObjectList<TGeminiChunk>;
    FOnExtractProgress: TGeminiExtractProgressEvent;

    procedure ParseRunSettings(AObj: TJSONObject);
    procedure ParseSystemInstruction(AObj: TJSONObject);
    procedure ParseChunks(AArr: TJSONArray);
    function ParseChunk(AObj: TJSONObject; AIndex: Integer): TGeminiChunk;
    function ParseParts(AArr: TJSONArray; AChunkIndex: Integer): TObjectList<TGeminiPart>;
    function ParseResource(AObj: TJSONObject; AChunkIndex: Integer): TGeminiResource;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    ///   Loads and parses a Gemini conversation file.
    /// </summary>
    /// <param name="AFileName">Full path to the Gemini file.</param>
    /// <exception cref="EFileNotFoundException">If the file does not exist.</exception>
    /// <exception cref="EJSONParseException">If the file contains invalid JSON.</exception>
    procedure LoadFromFile(const AFileName: string);

    /// <summary>
    ///   Loads and parses a Gemini conversation from a stream.
    /// </summary>
    /// <param name="AStream">Stream containing UTF-8 encoded JSON.</param>
    /// <exception cref="EJSONParseException">If the stream contains invalid JSON.</exception>
    procedure LoadFromStream(AStream: TStream);

    /// <summary>
    ///   Returns a flat array of all embedded resources (deduplicated).
    ///   Checks InlineImage at chunk level first, falls back to parts.
    /// </summary>
    /// <returns>Array of TGeminiResource references. Caller must NOT free these.</returns>
    function GetResources: TArray<TGeminiResource>;

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
    function ExtractAllResources(const AOutputDir: string;
      AThreaded: Boolean = True;
      const ANamePrefix: string = 'resource'): Integer;

    /// <summary>Total number of chunks in the conversation.</summary>
    function ChunkCount: Integer;
    /// <summary>Number of user message chunks.</summary>
    function UserChunkCount: Integer;
    /// <summary>Number of model response chunks (including thought chunks).</summary>
    function ModelChunkCount: Integer;
    /// <summary>Sum of all TokenCount values across chunks.</summary>
    function TotalTokenCount: Integer;

    /// <summary>Model run settings (temperature, model, etc.).</summary>
    property RunSettings: TGeminiRunSettings read FRunSettings;
    /// <summary>System instruction text. Empty if not provided.</summary>
    property SystemInstruction: string read FSystemInstruction;
    /// <summary>All conversation chunks in order.</summary>
    property Chunks: TObjectList<TGeminiChunk> read FChunks;
    /// <summary>Event fired during extraction to report progress.</summary>
    property OnExtractProgress: TGeminiExtractProgressEvent read FOnExtractProgress write FOnExtractProgress;
  end;

  /// <summary>Exception raised when a Gemini file cannot be parsed.</summary>
  EGeminiParseError = class(Exception);

implementation

{ Helper functions }

/// <summary>
///   Safely reads a string value from a JSON object.
///   Returns ADefault if the key is missing or the value is null.
/// </summary>
function JsonStr(AObj: TJSONObject; const AKey: string; const ADefault: string = ''): string;
var
  LVal: TJSONValue;
begin
  LVal := AObj.FindValue(AKey);
  if (LVal <> nil) and not (LVal is TJSONNull) then
    Result := LVal.Value
  else
    Result := ADefault;
end;

/// <summary>
///   Safely reads an integer value from a JSON object.
///   Returns ADefault if the key is missing, null, or not a number.
/// </summary>
function JsonInt(AObj: TJSONObject; const AKey: string; ADefault: Integer = 0): Integer;
var
  LVal: TJSONValue;
begin
  LVal := AObj.FindValue(AKey);
  if (LVal <> nil) and not (LVal is TJSONNull) then
  begin
    if LVal is TJSONNumber then
      Result := TJSONNumber(LVal).AsInt
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

/// <summary>
///   Safely reads a double value from a JSON object.
///   Returns ADefault if the key is missing, null, or not a number.
/// </summary>
function JsonFloat(AObj: TJSONObject; const AKey: string; ADefault: Double = NaN): Double;
var
  LVal: TJSONValue;
begin
  LVal := AObj.FindValue(AKey);
  if (LVal <> nil) and not (LVal is TJSONNull) then
  begin
    if LVal is TJSONNumber then
      Result := TJSONNumber(LVal).AsDouble
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

/// <summary>
///   Safely reads a boolean value from a JSON object.
///   Returns ADefault if the key is missing or null.
/// </summary>
function JsonBool(AObj: TJSONObject; const AKey: string; ADefault: Boolean = False): Boolean;
var
  LVal: TJSONValue;
begin
  LVal := AObj.FindValue(AKey);
  if (LVal <> nil) and not (LVal is TJSONNull) then
  begin
    if LVal is TJSONBool then
      Result := TJSONBool(LVal).AsBoolean
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

/// <summary>
///   Maps a MIME type string to a file extension.
/// </summary>
function MimeToExtension(const AMimeType: string): string;
var
  LLower: string;
begin
  LLower := LowerCase(AMimeType);
  if LLower = 'image/jpeg' then Result := '.jpg'
  else if LLower = 'image/png' then Result := '.png'
  else if LLower = 'image/gif' then Result := '.gif'
  else if LLower = 'image/webp' then Result := '.webp'
  else if LLower = 'image/bmp' then Result := '.bmp'
  else if LLower = 'image/svg+xml' then Result := '.svg'
  else if LLower = 'image/tiff' then Result := '.tiff'
  else if LLower = 'audio/mpeg' then Result := '.mp3'
  else if LLower = 'audio/wav' then Result := '.wav'
  else if LLower = 'audio/ogg' then Result := '.ogg'
  else if LLower = 'video/mp4' then Result := '.mp4'
  else if LLower = 'video/webm' then Result := '.webm'
  else if LLower = 'application/pdf' then Result := '.pdf'
  else if LLower = 'application/json' then Result := '.json'
  else if LLower = 'text/plain' then Result := '.txt'
  else if LLower = 'text/html' then Result := '.html'
  else if LLower = 'text/csv' then Result := '.csv'
  else Result := '.bin';
end;

/// <summary>
///   Formats a byte size into a human-readable string (B, KB, MB, GB).
/// </summary>
function FormatByteSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := Format('%d B', [ASize])
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f KB', [ASize / 1024.0])
  else if ASize < 1024 * 1024 * 1024 then
    Result := Format('%.1f MB', [ASize / (1024.0 * 1024.0)])
  else
    Result := Format('%.2f GB', [ASize / (1024.0 * 1024.0 * 1024.0)]);
end;

{ TGeminiResource }

constructor TGeminiResource.Create(const AMimeType, ABase64Data: string; AChunkIndex: Integer);
begin
  inherited Create;
  FMimeType := AMimeType;
  FBase64Data := ABase64Data;
  FIsDecoded := False;
  FChunkIndex := AChunkIndex;
end;

destructor TGeminiResource.Destroy;
begin
  ReleaseAll;
  inherited;
end;

procedure TGeminiResource.Decode;
begin
  if FIsDecoded then
    Exit;
  if FBase64Data = '' then
    raise EGeminiParseError.Create('Cannot decode resource: base64 data is empty or already released');
  FDecodedData := TNetEncoding.Base64.DecodeStringToBytes(FBase64Data);
  FIsDecoded := True;
  FBase64Data := '';
end;

procedure TGeminiResource.SaveToFile(const AFileName: string);
var
  LStream: TFileStream;
begin
  if not FIsDecoded then
    Decode;
  LStream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(FDecodedData) > 0 then
      LStream.WriteBuffer(FDecodedData[0], Length(FDecodedData));
  finally
    LStream.Free;
  end;
end;

procedure TGeminiResource.SaveToStream(AStream: TStream);
begin
  if not FIsDecoded then
    Decode;
  if Length(FDecodedData) > 0 then
    AStream.WriteBuffer(FDecodedData[0], Length(FDecodedData));
end;

function TGeminiResource.GetFileExtension: string;
begin
  Result := MimeToExtension(FMimeType);
end;

function TGeminiResource.GetDecodedSize: Int64;
begin
  if FIsDecoded then
    Result := Length(FDecodedData)
  else if FBase64Data <> '' then
    // Base64 expands data by ~4/3, so decoded size is roughly 3/4 of base64 length
    Result := (Length(FBase64Data) * 3) div 4
  else
    Result := 0;
end;

function TGeminiResource.GetBase64Size: Int64;
begin
  Result := Length(FBase64Data);
end;

procedure TGeminiResource.ReleaseBase64;
begin
  FBase64Data := '';
end;

procedure TGeminiResource.ReleaseAll;
begin
  FBase64Data := '';
  SetLength(FDecodedData, 0);
  FIsDecoded := False;
end;

{ TGeminiPart }

destructor TGeminiPart.Destroy;
begin
  FreeAndNil(FInlineData);
  inherited;
end;

{ TGeminiChunk }

constructor TGeminiChunk.Create;
begin
  inherited;
  FParts := TObjectList<TGeminiPart>.Create(True);
  FTokenCount := 0;
  FThinkingBudget := 0;
  FIsThought := False;
  FIsGeneratedUsingApiKey := False;
  FCreateTime := 0;
  FIndex := 0;
end;

destructor TGeminiChunk.Destroy;
begin
  FreeAndNil(FParts);
  FreeAndNil(FInlineImage);
  inherited;
end;

function TGeminiChunk.GetFullText: string;
var
  LSB: TStringBuilder;
  LPart: TGeminiPart;
begin
  if FParts.Count = 0 then
    Exit(FText);

  LSB := TStringBuilder.Create;
  try
    for LPart in FParts do
    begin
      if (not LPart.IsThought) and (LPart.Text <> '') then
        LSB.Append(LPart.Text);
    end;
    Result := LSB.ToString;
  finally
    LSB.Free;
  end;
end;

function TGeminiChunk.GetThinkingText: string;
var
  LSB: TStringBuilder;
  LPart: TGeminiPart;
begin
  if FIsThought and (FParts.Count = 0) then
    Exit(FText);

  LSB := TStringBuilder.Create;
  try
    for LPart in FParts do
    begin
      if LPart.IsThought and (LPart.Text <> '') then
        LSB.Append(LPart.Text);
    end;
    Result := LSB.ToString;
  finally
    LSB.Free;
  end;
end;

function TGeminiChunk.HasResource: Boolean;
var
  LPart: TGeminiPart;
begin
  if FInlineImage <> nil then
    Exit(True);
  for LPart in FParts do
    if LPart.InlineData <> nil then
      Exit(True);
  Result := False;
end;

function TGeminiChunk.GetResource: TGeminiResource;
var
  LPart: TGeminiPart;
begin
  if FInlineImage <> nil then
    Exit(FInlineImage);
  for LPart in FParts do
    if LPart.InlineData <> nil then
      Exit(LPart.InlineData);
  Result := nil;
end;

{ TGeminiRunSettings }

constructor TGeminiRunSettings.Create;
begin
  inherited;
  FTemperature := NaN;
  FTopP := NaN;
  FTopK := -1;
  FMaxOutputTokens := -1;
end;

{ TGeminiFile }

constructor TGeminiFile.Create;
begin
  inherited;
  FRunSettings := TGeminiRunSettings.Create;
  FChunks := TObjectList<TGeminiChunk>.Create(True);
end;

destructor TGeminiFile.Destroy;
begin
  FreeAndNil(FChunks);
  FreeAndNil(FRunSettings);
  inherited;
end;

procedure TGeminiFile.LoadFromFile(const AFileName: string);
var
  LStream: TFileStream;
begin
  if not FileExists(AFileName) then
    raise EFileNotFoundException.CreateFmt('File not found: %s', [AFileName]);
  LStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    LoadFromStream(LStream);
  finally
    LStream.Free;
  end;
end;

procedure TGeminiFile.LoadFromStream(AStream: TStream);
var
  LBytes: TBytes;
  LJsonStr: string;
  LRoot: TJSONValue;
  LObj: TJSONObject;
  LChunkedPrompt: TJSONObject;
  LChunksArr: TJSONArray;
begin
  // Read entire stream into a string
  SetLength(LBytes, AStream.Size - AStream.Position);
  if Length(LBytes) > 0 then
    AStream.ReadBuffer(LBytes[0], Length(LBytes));
  LJsonStr := TEncoding.UTF8.GetString(LBytes);
  SetLength(LBytes, 0); // free bytes early

  // Parse JSON
  LRoot := TJSONObject.ParseJSONValue(LJsonStr, False, True);
  if LRoot = nil then
    raise EGeminiParseError.Create('Failed to parse JSON: root value is nil');
  try
    if not (LRoot is TJSONObject) then
      raise EGeminiParseError.Create('Invalid Gemini file: root is not a JSON object');
    LObj := TJSONObject(LRoot);

    // Clear previous data
    FChunks.Clear;
    FSystemInstruction := '';

    // Parse sections
    if LObj.FindValue('runSettings') is TJSONObject then
      ParseRunSettings(TJSONObject(LObj.FindValue('runSettings')));

    if LObj.FindValue('systemInstruction') is TJSONObject then
      ParseSystemInstruction(TJSONObject(LObj.FindValue('systemInstruction')));

    if LObj.FindValue('chunkedPrompt') is TJSONObject then
    begin
      LChunkedPrompt := TJSONObject(LObj.FindValue('chunkedPrompt'));
      if LChunkedPrompt.FindValue('chunks') is TJSONArray then
      begin
        LChunksArr := TJSONArray(LChunkedPrompt.FindValue('chunks'));
        ParseChunks(LChunksArr);
      end;
    end;
  finally
    LRoot.Free;
  end;
end;

procedure TGeminiFile.ParseRunSettings(AObj: TJSONObject);
var
  LSafetyArr: TJSONArray;
  LModArr: TJSONArray;
  I: Integer;
  LSetting: TGeminiSafetySetting;
  LItem: TJSONObject;
begin
  FRunSettings.Model := JsonStr(AObj, 'model');
  FRunSettings.Temperature := JsonFloat(AObj, 'temperature');
  FRunSettings.TopP := JsonFloat(AObj, 'topP');
  FRunSettings.TopK := JsonInt(AObj, 'topK', -1);
  FRunSettings.MaxOutputTokens := JsonInt(AObj, 'maxOutputTokens', -1);
  FRunSettings.ResponseMimeType := JsonStr(AObj, 'responseMimeType');
  FRunSettings.EnableCodeExecution := JsonBool(AObj, 'enableCodeExecution');
  FRunSettings.EnableSearchAsATool := JsonBool(AObj, 'enableSearchAsATool');
  FRunSettings.EnableBrowseAsATool := JsonBool(AObj, 'enableBrowseAsATool');
  FRunSettings.EnableAutoFunctionResponse := JsonBool(AObj, 'enableAutoFunctionResponse');

  // Safety settings array
  if AObj.FindValue('safetySettings') is TJSONArray then
  begin
    LSafetyArr := TJSONArray(AObj.FindValue('safetySettings'));
    SetLength(FRunSettings.FSafetySettings, LSafetyArr.Count);
    for I := 0 to LSafetyArr.Count - 1 do
    begin
      if LSafetyArr.Items[I] is TJSONObject then
      begin
        LItem := TJSONObject(LSafetyArr.Items[I]);
        LSetting.Category := JsonStr(LItem, 'category');
        LSetting.Threshold := JsonStr(LItem, 'threshold');
        FRunSettings.FSafetySettings[I] := LSetting;
      end;
    end;
  end;

  // Response modalities array
  if AObj.FindValue('responseModalities') is TJSONArray then
  begin
    LModArr := TJSONArray(AObj.FindValue('responseModalities'));
    SetLength(FRunSettings.FResponseModalities, LModArr.Count);
    for I := 0 to LModArr.Count - 1 do
      FRunSettings.FResponseModalities[I] := LModArr.Items[I].Value;
  end;
end;

procedure TGeminiFile.ParseSystemInstruction(AObj: TJSONObject);
begin
  FSystemInstruction := JsonStr(AObj, 'text');
end;

procedure TGeminiFile.ParseChunks(AArr: TJSONArray);
var
  I: Integer;
  LChunk: TGeminiChunk;
begin
  for I := 0 to AArr.Count - 1 do
  begin
    if AArr.Items[I] is TJSONObject then
    begin
      LChunk := ParseChunk(TJSONObject(AArr.Items[I]), I);
      FChunks.Add(LChunk);
    end;
  end;
end;

function TGeminiFile.ParseChunk(AObj: TJSONObject; AIndex: Integer): TGeminiChunk;
var
  LRoleStr: string;
  LSafetyArr: TJSONArray;
  LSigArr: TJSONArray;
  LPartsArr: TJSONArray;
  LImgObj: TJSONObject;
  LDriveObj: TJSONObject;
  LCreateTimeStr: string;
  I: Integer;
  LRating: TGeminiSafetyRating;
  LItem: TJSONObject;
begin
  Result := TGeminiChunk.Create;
  try
    Result.Index := AIndex;
    Result.Text := JsonStr(AObj, 'text');

    // Role
    LRoleStr := LowerCase(JsonStr(AObj, 'role'));
    if LRoleStr = 'model' then
      Result.Role := grModel
    else
      Result.Role := grUser;

    Result.TokenCount := JsonInt(AObj, 'tokenCount');
    Result.IsThought := JsonBool(AObj, 'isThought');
    Result.ThinkingBudget := JsonInt(AObj, 'thinkingBudget');
    Result.FinishReason := JsonStr(AObj, 'finishReason');
    Result.ErrorMessage := JsonStr(AObj, 'errorMessage');
    Result.IsGeneratedUsingApiKey := JsonBool(AObj, 'isGeneratedUsingApiKey');
    Result.DriveImageId := '';

    // CreateTime (ISO 8601)
    LCreateTimeStr := JsonStr(AObj, 'createTime');
    if LCreateTimeStr <> '' then
    begin
      try
        Result.CreateTime := ISO8601ToDate(LCreateTimeStr, False);
      except
        Result.CreateTime := 0;
      end;
    end;

    // DriveImage
    if AObj.FindValue('driveImage') is TJSONObject then
    begin
      LDriveObj := TJSONObject(AObj.FindValue('driveImage'));
      Result.DriveImageId := JsonStr(LDriveObj, 'id');
    end;

    // InlineImage (chunk-level)
    if AObj.FindValue('inlineImage') is TJSONObject then
    begin
      LImgObj := TJSONObject(AObj.FindValue('inlineImage'));
      Result.InlineImage := ParseResource(LImgObj, AIndex);
    end;

    // Safety ratings
    if AObj.FindValue('safetyRatings') is TJSONArray then
    begin
      LSafetyArr := TJSONArray(AObj.FindValue('safetyRatings'));
      SetLength(Result.FSafetyRatings, LSafetyArr.Count);
      for I := 0 to LSafetyArr.Count - 1 do
      begin
        if LSafetyArr.Items[I] is TJSONObject then
        begin
          LItem := TJSONObject(LSafetyArr.Items[I]);
          LRating.Category := JsonStr(LItem, 'category');
          LRating.Probability := JsonStr(LItem, 'probability');
          Result.FSafetyRatings[I] := LRating;
        end;
      end;
    end;

    // Thought signatures
    if AObj.FindValue('thoughtSignatures') is TJSONArray then
    begin
      LSigArr := TJSONArray(AObj.FindValue('thoughtSignatures'));
      SetLength(Result.FThoughtSignatures, LSigArr.Count);
      for I := 0 to LSigArr.Count - 1 do
        Result.FThoughtSignatures[I] := LSigArr.Items[I].Value;
    end;

    // Parts
    if AObj.FindValue('parts') is TJSONArray then
    begin
      LPartsArr := TJSONArray(AObj.FindValue('parts'));
      Result.FParts.Free;
      Result.FParts := ParseParts(LPartsArr, AIndex);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TGeminiFile.ParseParts(AArr: TJSONArray; AChunkIndex: Integer): TObjectList<TGeminiPart>;
var
  I: Integer;
  LPartObj: TJSONObject;
  LPart: TGeminiPart;
  LInlineObj: TJSONObject;
begin
  Result := TObjectList<TGeminiPart>.Create(True);
  try
    for I := 0 to AArr.Count - 1 do
    begin
      if AArr.Items[I] is TJSONObject then
      begin
        LPartObj := TJSONObject(AArr.Items[I]);
        LPart := TGeminiPart.Create;
        try
          LPart.Text := JsonStr(LPartObj, 'text');
          LPart.IsThought := JsonBool(LPartObj, 'thought');
          LPart.ThoughtSignature := JsonStr(LPartObj, 'thoughtSignature');

          // Inline data within a part
          if LPartObj.FindValue('inlineData') is TJSONObject then
          begin
            LInlineObj := TJSONObject(LPartObj.FindValue('inlineData'));
            LPart.InlineData := ParseResource(LInlineObj, AChunkIndex);
          end;

          Result.Add(LPart);
        except
          LPart.Free;
          raise;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TGeminiFile.ParseResource(AObj: TJSONObject; AChunkIndex: Integer): TGeminiResource;
var
  LMime, LData: string;
begin
  LMime := JsonStr(AObj, 'mimeType');
  LData := JsonStr(AObj, 'data');
  if (LMime = '') or (LData = '') then
    Exit(nil);
  Result := TGeminiResource.Create(LMime, LData, AChunkIndex);
end;

function TGeminiFile.GetResources: TArray<TGeminiResource>;
var
  LList: TList<TGeminiResource>;
  LChunk: TGeminiChunk;
  LPart: TGeminiPart;
begin
  LList := TList<TGeminiResource>.Create;
  try
    for LChunk in FChunks do
    begin
      // Primary: chunk-level InlineImage
      if LChunk.InlineImage <> nil then
      begin
        LList.Add(LChunk.InlineImage);
        Continue; // Skip parts -- they contain the same data
      end;
      // Fallback: scan parts for InlineData
      for LPart in LChunk.Parts do
      begin
        if LPart.InlineData <> nil then
        begin
          LList.Add(LPart.InlineData);
          Break; // One resource per chunk is sufficient for deduplication
        end;
      end;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TGeminiFile.GetResourceCount: Integer;
begin
  Result := Length(GetResources);
end;

function TGeminiFile.ExtractAllResources(const AOutputDir: string;
  AThreaded: Boolean; const ANamePrefix: string): Integer;
var
  LResources: TArray<TGeminiResource>;
  LAbsDir: string;
  I: Integer;
  LFileName: string;
  LPadWidth: Integer;
begin
  LResources := GetResources;
  Result := Length(LResources);
  if Result = 0 then
    Exit;

  LAbsDir := TPath.GetFullPath(AOutputDir);
  ForceDirectories(LAbsDir);
  LPadWidth := Length(IntToStr(Result));
  if LPadWidth < 3 then
    LPadWidth := 3;

  if AThreaded and (Result > 1) then
  begin
    TParallel.&For(0, Result - 1,
      procedure(AIdx: Integer)
      var
        LFN: string;
      begin
        LFN := TPath.Combine(LAbsDir,
          Format('%s_%.*d%s', [ANamePrefix, LPadWidth, AIdx, LResources[AIdx].GetFileExtension]));
        LResources[AIdx].SaveToFile(LFN);
        if Assigned(FOnExtractProgress) then
          FOnExtractProgress(AIdx, Length(LResources), LFN);
      end);
  end
  else
  begin
    for I := 0 to Result - 1 do
    begin
      LFileName := TPath.Combine(LAbsDir,
        Format('%s_%.*d%s', [ANamePrefix, LPadWidth, I, LResources[I].GetFileExtension]));
      LResources[I].SaveToFile(LFileName);
      if Assigned(FOnExtractProgress) then
        FOnExtractProgress(I, Result, LFileName);
    end;
  end;
end;

function TGeminiFile.ChunkCount: Integer;
begin
  Result := FChunks.Count;
end;

function TGeminiFile.UserChunkCount: Integer;
var
  LChunk: TGeminiChunk;
begin
  Result := 0;
  for LChunk in FChunks do
    if LChunk.Role = grUser then
      Inc(Result);
end;

function TGeminiFile.ModelChunkCount: Integer;
var
  LChunk: TGeminiChunk;
begin
  Result := 0;
  for LChunk in FChunks do
    if LChunk.Role = grModel then
      Inc(Result);
end;

function TGeminiFile.TotalTokenCount: Integer;
var
  LChunk: TGeminiChunk;
begin
  Result := 0;
  for LChunk in FChunks do
    Inc(Result, LChunk.TokenCount);
end;

end.
