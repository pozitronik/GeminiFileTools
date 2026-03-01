/// <summary>
///   JSON parsing for Gemini conversation files (Pure Fabrication).
///   Single responsibility: transform JSON stream into domain model objects.
///   The parser is the Creator (GRASP) -- it has the initialization data
///   from JSON and creates all model objects.
/// </summary>
unit GeminiFile.Parser;

interface

uses
	System.SysUtils,
	System.Classes,
	System.JSON,
	System.DateUtils,
	System.Math,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model;

type
	/// <summary>
	///   Interface for parsing Gemini conversation files.
	///   Allows substitution of parsing strategy (DIP).
	/// </summary>
	IGeminiFileParser = interface
		['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
		/// <summary>
		///   Parses a stream containing a Gemini conversation JSON file.
		///   Populates the provided data record with parsed results.
		/// </summary>
		/// <param name="AStream">Stream containing UTF-8 encoded JSON.</param>
		/// <param name="ARunSettings">Run settings object to populate (caller owns).</param>
		/// <param name="AChunks">Chunk list to populate (caller owns).</param>
		/// <returns>System instruction text.</returns>
		/// <exception cref="EGeminiParseError">If the stream contains invalid JSON.</exception>
		function Parse(AStream: TStream; ARunSettings: TGeminiRunSettings; AChunks: TObjectList<TGeminiChunk>): string;
	end;

	/// <summary>
	///   Default JSON parser implementation for Gemini conversation files.
	/// </summary>
	TGeminiFileParser = class(TInterfacedObject, IGeminiFileParser)
	private
		procedure ParseRunSettings(AObj: TJSONObject; ARunSettings: TGeminiRunSettings);
		function ParseSystemInstruction(AObj: TJSONObject): string;
		procedure ParseChunks(AArr: TJSONArray; AChunks: TObjectList<TGeminiChunk>);
		function ParseChunk(AObj: TJSONObject; AIndex: Integer): TGeminiChunk;
		procedure ParsePartsInto(AArr: TJSONArray; AChunkIndex: Integer; AParts: TObjectList<TGeminiPart>);
		function ParseResource(AObj: TJSONObject; AChunkIndex: Integer): TGeminiResource;
	public
		/// <summary>
		///   Parses a stream containing a Gemini conversation JSON file.
		/// </summary>
		/// <param name="AStream">Stream containing UTF-8 encoded JSON.</param>
		/// <param name="ARunSettings">Run settings object to populate (caller owns).</param>
		/// <param name="AChunks">Chunk list to populate (caller owns).</param>
		/// <returns>System instruction text.</returns>
		/// <exception cref="EGeminiParseError">If the stream contains invalid JSON.</exception>
		function Parse(AStream: TStream; ARunSettings: TGeminiRunSettings; AChunks: TObjectList<TGeminiChunk>): string;
	end;

	/// <summary>
	///   Safely reads a string value from a JSON object.
	///   Returns ADefault if the key is missing or the value is null.
	/// </summary>
	/// <param name="AObj">JSON object to read from.</param>
	/// <param name="AKey">Key to look up.</param>
	/// <param name="ADefault">Default value if key is missing or null.</param>
	/// <returns>String value or default.</returns>
function JsonStr(AObj: TJSONObject; const AKey: string; const ADefault: string = ''): string;

/// <summary>
///   Safely reads an integer value from a JSON object.
///   Returns ADefault if the key is missing, null, or not a number.
/// </summary>
/// <param name="AObj">JSON object to read from.</param>
/// <param name="AKey">Key to look up.</param>
/// <param name="ADefault">Default value if key is missing, null, or wrong type.</param>
/// <returns>Integer value or default.</returns>
function JsonInt(AObj: TJSONObject; const AKey: string; ADefault: Integer = 0): Integer;

/// <summary>
///   Safely reads a double value from a JSON object.
///   Returns ADefault if the key is missing, null, or not a number.
/// </summary>
/// <param name="AObj">JSON object to read from.</param>
/// <param name="AKey">Key to look up.</param>
/// <param name="ADefault">Default value if key is missing, null, or wrong type.</param>
/// <returns>Double value or default.</returns>
function JsonFloat(AObj: TJSONObject; const AKey: string; ADefault: Double = NaN): Double;

/// <summary>
///   Safely reads a boolean value from a JSON object.
///   Returns ADefault if the key is missing, null, or not a boolean.
/// </summary>
/// <param name="AObj">JSON object to read from.</param>
/// <param name="AKey">Key to look up.</param>
/// <param name="ADefault">Default value if key is missing, null, or wrong type.</param>
/// <returns>Boolean value or default.</returns>
function JsonBool(AObj: TJSONObject; const AKey: string; ADefault: Boolean = False): Boolean;

implementation

{JSON helper functions}

function JsonStr(AObj: TJSONObject; const AKey: string; const ADefault: string = ''): string;
var
	LVal: TJSONValue;
begin
	LVal := AObj.FindValue(AKey);
	if (LVal <> nil) and not(LVal is TJSONNull) then
		Result := LVal.Value
	else
		Result := ADefault;
end;

function JsonInt(AObj: TJSONObject; const AKey: string; ADefault: Integer = 0): Integer;
var
	LVal: TJSONValue;
begin
	LVal := AObj.FindValue(AKey);
	if (LVal <> nil) and not(LVal is TJSONNull) then
	begin
		if LVal is TJSONNumber then
			Result := TJSONNumber(LVal).AsInt
		else
			Result := ADefault;
	end
	else
		Result := ADefault;
end;

function JsonFloat(AObj: TJSONObject; const AKey: string; ADefault: Double = NaN): Double;
var
	LVal: TJSONValue;
begin
	LVal := AObj.FindValue(AKey);
	if (LVal <> nil) and not(LVal is TJSONNull) then
	begin
		if LVal is TJSONNumber then
			Result := TJSONNumber(LVal).AsDouble
		else
			Result := ADefault;
	end
	else
		Result := ADefault;
end;

function JsonBool(AObj: TJSONObject; const AKey: string; ADefault: Boolean = False): Boolean;
var
	LVal: TJSONValue;
begin
	LVal := AObj.FindValue(AKey);
	if (LVal <> nil) and not(LVal is TJSONNull) then
	begin
		if LVal is TJSONBool then
			Result := TJSONBool(LVal).AsBoolean
		else
			Result := ADefault;
	end
	else
		Result := ADefault;
end;

{TGeminiFileParser}

function TGeminiFileParser.Parse(AStream: TStream; ARunSettings: TGeminiRunSettings; AChunks: TObjectList<TGeminiChunk>): string;
var
	LBytes: TBytes;
	LJsonStr: string;
	LRoot: TJSONValue;
	LObj: TJSONObject;
	LChunkedPrompt: TJSONObject;
	LChunksArr: TJSONArray;
	LStart: Integer;
begin
	Result := '';

	// Read entire stream into a byte array
	SetLength(LBytes, AStream.Size - AStream.Position);
	if Length(LBytes) > 0 then
		AStream.ReadBuffer(LBytes[0], Length(LBytes));

	// Quick sanity check: first non-whitespace byte must be '{' for valid JSON object.
	// This catches binary files (ZIP, MP4, images, etc.) before expensive UTF-8 decoding.
	LStart := 0;
	// Skip UTF-8 BOM if present
	if (Length(LBytes) >= 3) and (LBytes[0] = $EF) and (LBytes[1] = $BB) and (LBytes[2] = $BF) then
		LStart := 3;
	// Skip leading ASCII whitespace
	while (LStart < Length(LBytes)) and (LBytes[LStart] in [$09, $0A, $0D, $20]) do
		Inc(LStart);
	if (LStart >= Length(LBytes)) or (LBytes[LStart] <> Ord('{')) then
		raise EGeminiParseError.Create('Not a valid Gemini file: content does not start with a JSON object');

	LJsonStr := TEncoding.UTF8.GetString(LBytes);
	SetLength(LBytes, 0); // free bytes early

	// Parse JSON
	try
		LRoot := TJSONObject.ParseJSONValue(LJsonStr, False, True);
	except
		on E: Exception do
			raise EGeminiParseError.Create('Failed to parse JSON: ' + E.Message);
	end;
	if LRoot = nil then
		raise EGeminiParseError.Create('Failed to parse JSON: parser returned nil');
	try
		LObj := TJSONObject(LRoot);

		// Clear previous data
		AChunks.Clear;

		// Parse sections
		if LObj.FindValue('runSettings') is TJSONObject then
			ParseRunSettings(TJSONObject(LObj.FindValue('runSettings')), ARunSettings);

		if LObj.FindValue('systemInstruction') is TJSONObject then
			Result := ParseSystemInstruction(TJSONObject(LObj.FindValue('systemInstruction')));

		if LObj.FindValue('chunkedPrompt') is TJSONObject then
		begin
			LChunkedPrompt := TJSONObject(LObj.FindValue('chunkedPrompt'));
			if LChunkedPrompt.FindValue('chunks') is TJSONArray then
			begin
				LChunksArr := TJSONArray(LChunkedPrompt.FindValue('chunks'));
				ParseChunks(LChunksArr, AChunks);
			end;
		end;
	finally
		LRoot.Free;
	end;
end;

procedure TGeminiFileParser.ParseRunSettings(AObj: TJSONObject; ARunSettings: TGeminiRunSettings);
var
	LSafetyArr: TJSONArray;
	LModArr: TJSONArray;
	I: Integer;
	LSetting: TGeminiSafetySetting;
	LItem: TJSONObject;
	LSafetySettings: TArray<TGeminiSafetySetting>;
	LModalities: TArray<string>;
begin
	ARunSettings.Model := JsonStr(AObj, 'model');
	ARunSettings.Temperature := JsonFloat(AObj, 'temperature');
	ARunSettings.TopP := JsonFloat(AObj, 'topP');
	ARunSettings.TopK := JsonInt(AObj, 'topK', -1);
	ARunSettings.MaxOutputTokens := JsonInt(AObj, 'maxOutputTokens', -1);
	ARunSettings.ResponseMimeType := JsonStr(AObj, 'responseMimeType');
	ARunSettings.EnableCodeExecution := JsonBool(AObj, 'enableCodeExecution');
	ARunSettings.EnableSearchAsATool := JsonBool(AObj, 'enableSearchAsATool');
	ARunSettings.EnableBrowseAsATool := JsonBool(AObj, 'enableBrowseAsATool');
	ARunSettings.EnableAutoFunctionResponse := JsonBool(AObj, 'enableAutoFunctionResponse');

	// Safety settings array
	if AObj.FindValue('safetySettings') is TJSONArray then
	begin
		LSafetyArr := TJSONArray(AObj.FindValue('safetySettings'));
		SetLength(LSafetySettings, LSafetyArr.Count);
		for I := 0 to LSafetyArr.Count - 1 do
		begin
			if LSafetyArr.Items[I] is TJSONObject then
			begin
				LItem := TJSONObject(LSafetyArr.Items[I]);
				LSetting.Category := JsonStr(LItem, 'category');
				LSetting.Threshold := JsonStr(LItem, 'threshold');
				LSafetySettings[I] := LSetting;
			end;
		end;
		ARunSettings.SafetySettings := LSafetySettings;
	end;

	// Response modalities array
	if AObj.FindValue('responseModalities') is TJSONArray then
	begin
		LModArr := TJSONArray(AObj.FindValue('responseModalities'));
		SetLength(LModalities, LModArr.Count);
		for I := 0 to LModArr.Count - 1 do
			LModalities[I] := LModArr.Items[I].Value;
		ARunSettings.ResponseModalities := LModalities;
	end;
end;

function TGeminiFileParser.ParseSystemInstruction(AObj: TJSONObject): string;
begin
	Result := JsonStr(AObj, 'text');
end;

procedure TGeminiFileParser.ParseChunks(AArr: TJSONArray; AChunks: TObjectList<TGeminiChunk>);
var
	I: Integer;
	LChunk: TGeminiChunk;
begin
	for I := 0 to AArr.Count - 1 do
	begin
		if AArr.Items[I] is TJSONObject then
		begin
			LChunk := ParseChunk(TJSONObject(AArr.Items[I]), I);
			AChunks.Add(LChunk);
		end;
	end;
end;

function TGeminiFileParser.ParseChunk(AObj: TJSONObject; AIndex: Integer): TGeminiChunk;
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
	LSafetyRatings: TArray<TGeminiSafetyRating>;
	LSignatures: TArray<string>;
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
			SetLength(LSafetyRatings, LSafetyArr.Count);
			for I := 0 to LSafetyArr.Count - 1 do
			begin
				if LSafetyArr.Items[I] is TJSONObject then
				begin
					LItem := TJSONObject(LSafetyArr.Items[I]);
					LRating.Category := JsonStr(LItem, 'category');
					LRating.Probability := JsonStr(LItem, 'probability');
					LSafetyRatings[I] := LRating;
				end;
			end;
			Result.SafetyRatings := LSafetyRatings;
		end;

		// Thought signatures
		if AObj.FindValue('thoughtSignatures') is TJSONArray then
		begin
			LSigArr := TJSONArray(AObj.FindValue('thoughtSignatures'));
			SetLength(LSignatures, LSigArr.Count);
			for I := 0 to LSigArr.Count - 1 do
				LSignatures[I] := LSigArr.Items[I].Value;
			Result.ThoughtSignatures := LSignatures;
		end;

		// Parts
		if AObj.FindValue('parts') is TJSONArray then
		begin
			LPartsArr := TJSONArray(AObj.FindValue('parts'));
			ParsePartsInto(LPartsArr, AIndex, Result.Parts);
		end;
	except
		Result.Free;
		raise;
	end;
end;

procedure TGeminiFileParser.ParsePartsInto(AArr: TJSONArray; AChunkIndex: Integer; AParts: TObjectList<TGeminiPart>);
var
	I: Integer;
	LPartObj: TJSONObject;
	LPart: TGeminiPart;
	LInlineObj: TJSONObject;
begin
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

				AParts.Add(LPart);
			except
				LPart.Free;
				raise;
			end;
		end;
	end;
end;

function TGeminiFileParser.ParseResource(AObj: TJSONObject; AChunkIndex: Integer): TGeminiResource;
var
	LMime, LData: string;
begin
	LMime := JsonStr(AObj, 'mimeType');
	LData := JsonStr(AObj, 'data');
	if (LMime = '') or (LData = '') then
		Exit(nil);
	Result := TGeminiResource.Create(LMime, LData, AChunkIndex);
end;

end.
