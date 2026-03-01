/// <summary>
///   Domain model classes for Gemini conversation files.
///   Contains data model with behavior relating to own data (Information Expert).
///   No dependency on System.JSON -- model knows nothing about serialization.
/// </summary>
unit GeminiFile.Model;

interface

uses
	System.SysUtils,
	System.Classes,
	System.Math,
	System.NetEncoding,
	System.Generics.Collections,
	GeminiFile.Types;

type
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
		/// <exception cref="EGeminiParseError">If base64 data is empty or already released.</exception>
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
		/// <summary>Raw base64-encoded data string. Empty if already decoded and released.</summary>
		property Base64Data: string read FBase64Data;
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

implementation

{TGeminiResource}

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

{TGeminiPart}

destructor TGeminiPart.Destroy;
begin
	FreeAndNil(FInlineData);
	inherited;
end;

{TGeminiChunk}

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

{TGeminiRunSettings}

constructor TGeminiRunSettings.Create;
begin
	inherited;
	FTemperature := NaN;
	FTopP := NaN;
	FTopK := -1;
	FMaxOutputTokens := -1;
end;

end.
