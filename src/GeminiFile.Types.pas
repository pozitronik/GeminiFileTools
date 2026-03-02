/// <summary>
///   Value types, enumerations, records, and utility functions for the
///   GeminiFile library. No class dependencies -- pure value types only.
/// </summary>
unit GeminiFile.Types;

interface

uses
	System.SysUtils;

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
	///   Callback invoked during resource extraction to report progress.
	///   Note: in threaded mode, this may be called from worker threads.
	///   The consumer is responsible for thread safety if needed.
	/// </summary>
	/// <param name="AIndex">Zero-based index of the resource being extracted.</param>
	/// <param name="ATotal">Total number of resources.</param>
	/// <param name="AFileName">Output file name.</param>
	TGeminiExtractProgressEvent = reference to procedure(AIndex, ATotal: Integer; const AFileName: string);

	/// <summary>Exception raised when a Gemini file cannot be parsed.</summary>
	EGeminiParseError = class(Exception);

	/// <summary>
	///   Resource info passed to formatters for link/embed generation.
	///   Value record -- decouples formatters from TGeminiResource lifetime.
	/// </summary>
	TFormatterResourceInfo = record
		/// <summary>Relative path for use in links, e.g. 'resources/resource_001.png'.</summary>
		FileName: string;
		/// <summary>MIME type, e.g. 'image/jpeg'.</summary>
		MimeType: string;
		/// <summary>Raw base64-encoded data. Only populated for embedded HTML formatter.</summary>
		Base64Data: string;
		/// <summary>Estimated decoded size in bytes.</summary>
		DecodedSize: Int64;
		/// <summary>Index of the parent chunk in the conversation.</summary>
		ChunkIndex: Integer;
	end;

	/// <summary>
	///   Maps a MIME type string to a file extension (with leading dot).
	///   Falls back to '.bin' for unknown types. Case-insensitive.
	/// </summary>
	/// <param name="AMimeType">MIME type, e.g. 'image/jpeg'.</param>
	/// <returns>File extension string, e.g. '.jpg', '.png', '.bin'.</returns>
function MimeToExtension(const AMimeType: string): string;

/// <summary>
///   Formats a byte size into a human-readable string (B, KB, MB, GB).
/// </summary>
/// <param name="ASize">Size in bytes.</param>
/// <returns>Formatted string, e.g. '1.5 MB'.</returns>
function FormatByteSize(ASize: Int64): string;

/// <summary>
///   Finds a resource info record matching the given chunk index.
/// </summary>
/// <param name="AResources">Array of resource info records to search.</param>
/// <param name="AChunkIndex">Chunk index to match.</param>
/// <param name="AInfo">Output: matched resource info record.</param>
/// <returns>True if a matching resource was found.</returns>
function FindResourceForChunk(const AResources: TArray<TFormatterResourceInfo>; AChunkIndex: Integer; out AInfo: TFormatterResourceInfo): Boolean;

/// <summary>
///   Formats a TDateTime as 'YYYY-MM-DD HH:MM:SS' for display in formatters.
///   Returns empty string when ADateTime is zero (unset/missing).
/// </summary>
/// <param name="ADateTime">UTC date/time value from chunk CreateTime.</param>
/// <returns>Formatted string or '' if ADateTime = 0.</returns>
function FormatCreateTime(ADateTime: TDateTime): string;

/// <summary>
///   Computes the zero-padded width for resource filenames (minimum 3 digits).
/// </summary>
/// <param name="ACount">Total number of resources.</param>
/// <returns>Number of digits to use for the numeric index.</returns>
function ResourcePadWidth(ACount: Integer): Integer;

implementation

function MimeToExtension(const AMimeType: string): string;
var
	LLower: string;
begin
	LLower := LowerCase(AMimeType);
	if LLower = 'image/jpeg' then
		Result := '.jpg'
	else if LLower = 'image/png' then
		Result := '.png'
	else if LLower = 'image/gif' then
		Result := '.gif'
	else if LLower = 'image/webp' then
		Result := '.webp'
	else if LLower = 'image/bmp' then
		Result := '.bmp'
	else if LLower = 'image/svg+xml' then
		Result := '.svg'
	else if LLower = 'image/tiff' then
		Result := '.tiff'
	else if LLower = 'audio/mpeg' then
		Result := '.mp3'
	else if LLower = 'audio/wav' then
		Result := '.wav'
	else if LLower = 'audio/ogg' then
		Result := '.ogg'
	else if LLower = 'video/mp4' then
		Result := '.mp4'
	else if LLower = 'video/webm' then
		Result := '.webm'
	else if LLower = 'application/pdf' then
		Result := '.pdf'
	else if LLower = 'application/json' then
		Result := '.json'
	else if LLower = 'text/plain' then
		Result := '.txt'
	else if LLower = 'text/html' then
		Result := '.html'
	else if LLower = 'text/csv' then
		Result := '.csv'
	else
		Result := '.bin';
end;

function FindResourceForChunk(const AResources: TArray<TFormatterResourceInfo>; AChunkIndex: Integer; out AInfo: TFormatterResourceInfo): Boolean;
var
	I: Integer;
begin
	for I := 0 to High(AResources) do
		if AResources[I].ChunkIndex = AChunkIndex then
		begin
			AInfo := AResources[I];
			Exit(True);
		end;
	Result := False;
end;

function FormatCreateTime(ADateTime: TDateTime): string;
begin
	if ADateTime = 0 then
		Result := ''
	else
		Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', ADateTime);
end;

function FormatByteSize(ASize: Int64): string;
var
	LFmt: TFormatSettings;
begin
	LFmt := TFormatSettings.Invariant;
	if ASize < 1024 then
		Result := Format('%d B', [ASize])
	else if ASize < 1024 * 1024 then
		Result := Format('%.1f KB', [ASize / 1024.0], LFmt)
	else if ASize < 1024 * 1024 * 1024 then
		Result := Format('%.1f MB', [ASize / (1024.0 * 1024.0)], LFmt)
	else
		Result := Format('%.2f GB', [ASize / (1024.0 * 1024.0 * 1024.0)], LFmt);
end;

function ResourcePadWidth(ACount: Integer): Integer;
begin
	Result := Length(IntToStr(ACount));
	if Result < 3 then
		Result := 3;
end;

end.
