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

end.
