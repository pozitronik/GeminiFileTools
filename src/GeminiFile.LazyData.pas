/// <summary>
///   Pre-scanner and lazy-load utilities for large Gemini files.
///   Strips base64 "data" values from raw JSON bytes, replacing them with
///   lightweight placeholders. The original byte offsets are recorded so
///   base64 content can be loaded on demand from the source file.
/// </summary>
unit GeminiFile.LazyData;

interface

uses
	System.SysUtils,
	System.Classes;

type
	/// <summary>
	///   Byte-level location of a base64 value inside the original file.
	///   Offsets point to the content between the opening and closing quotes.
	/// </summary>
	TBase64Location = record
		ByteOffset: Int64; // position in file where base64 content starts (after opening quote)
		ByteLength: Int64; // byte count of base64 content (excluding quotes)
	end;

	/// <summary>
	///   Result of pre-scanning a Gemini file: stripped JSON bytes + location map.
	/// </summary>
	TPreScanResult = record
		StrippedJsonBytes: TBytes; // UTF-8 bytes with base64 replaced by __LAZY:N
		Locations: TArray<TBase64Location>; // indexed by placeholder N
	end;

	/// <summary>Raised when lazy loading of base64 data fails.</summary>
	ELazyLoadError = class(Exception);

	/// <summary>
	///   Pre-scans raw file bytes to find "data" key-value pairs and replaces
	///   large base64 string values with "__LAZY:N" placeholders.
	///   Returns the stripped JSON as UTF-8 bytes and a map of original byte locations.
	/// </summary>
	/// <param name="ABytes">Raw file bytes (UTF-8 encoded JSON).</param>
	/// <param name="AThreshold">Minimum byte length of a "data" value to strip. Default 1024.</param>
	/// <returns>Pre-scan result with stripped JSON bytes and location array.</returns>
function PreScanGeminiFile(const ABytes: TBytes; AThreshold: Integer = 1024): TPreScanResult;

/// <summary>
///   Loads a base64 string from the original file at the specified byte location.
///   Thread-safe: each call opens its own file handle with shared read access.
/// </summary>
/// <param name="AFilePath">Path to the original Gemini file.</param>
/// <param name="ALocation">Byte offset and length of the base64 content.</param>
/// <returns>UTF-8 decoded string containing the base64 data.</returns>
/// <exception cref="ELazyLoadError">If file cannot be read or offset is invalid.</exception>
function LoadBase64FromFile(const AFilePath: string; const ALocation: TBase64Location): string;

implementation

/// <summary>
///   Single-pass byte-level state machine that identifies JSON "data" keys
///   followed by string values, and replaces large values with placeholders.
///   Multi-byte UTF-8 passes through safely (continuation bytes $80..$BF
///   never match ASCII structural characters).
/// </summary>
function PreScanGeminiFile(const ABytes: TBytes; AThreshold: Integer): TPreScanResult;
var
	LOut: TMemoryStream;
	LLocations: TArray<TBase64Location>;
	LLocationCount: Integer;
	LLen: Integer;
	LPos: Integer;
	LKeyStart, LKeyEnd: Integer;
	LValStart, LValEnd: Integer;
	LIsDataKey: Boolean;
	LValLen: Integer;
	LPlaceholder: UTF8String;
	LLocation: TBase64Location;

	/// <summary>Writes a range of source bytes to the output stream.</summary>
	procedure FlushTo(AUpTo: Integer);
	var
		LCount: Integer;
	begin
		// LPos is the "already flushed up to" marker
		LCount := AUpTo - LPos;
		if LCount > 0 then
			LOut.WriteBuffer(ABytes[LPos], LCount);
	end;

/// <summary>
///   Scans forward from the current position to find the end of a JSON string.
///   Handles backslash escapes. Returns the index of the closing quote,
///   or -1 if no closing quote is found.
/// </summary>
	function FindStringEnd(AFrom: Integer): Integer;
	var
		LI: Integer;
	begin
		LI := AFrom;
		while LI < LLen do
		begin
			if ABytes[LI] = Ord('\') then
			begin
				Inc(LI, 2); // skip escaped char
				Continue;
			end;
			if ABytes[LI] = Ord('"') then
				Exit(LI);
			Inc(LI);
		end;
		Result := -1;
	end;

/// <summary>
///   Checks if bytes at [AStart..AEnd) represent the string "data".
///   AStart is the byte after the opening quote, AEnd is the closing quote.
/// </summary>
	function IsDataKey(AStart, AEnd: Integer): Boolean;
	begin
		Result := (AEnd - AStart = 4) and (ABytes[AStart] = Ord('d')) and (ABytes[AStart + 1] = Ord('a')) and (ABytes[AStart + 2] = Ord('t')) and (ABytes[AStart + 3] = Ord('a'));
	end;

/// <summary>Skips ASCII whitespace bytes from the given position.</summary>
	function SkipWhitespace(AFrom: Integer): Integer;
	begin
		Result := AFrom;
		while (Result < LLen) and (ABytes[Result] in [$09, $0A, $0D, $20]) do
			Inc(Result);
	end;

begin
	LLen := Length(ABytes);
	LLocationCount := 0;
	SetLength(LLocations, 16);

	LOut := TMemoryStream.Create;
	try
		// Pre-allocate: stripped JSON is at most as large as the input
		// (for files without large data values), but typically much smaller
		if LLen < 1024 * 1024 then
			LOut.Size := LLen
		else
			LOut.Size := LLen div 4; // conservative for large files

		LOut.Position := 0;

		LPos := 0;

		// Skip UTF-8 BOM
		if (LLen >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
			LPos := 3;

		// Main scan loop: find each opening quote at top level or nested
		// We scan byte-by-byte, tracking only quote positions
		LKeyStart := LPos;
		while LKeyStart < LLen do
		begin
			// Find next opening quote
			while (LKeyStart < LLen) and (ABytes[LKeyStart] <> Ord('"')) do
				Inc(LKeyStart);
			if LKeyStart >= LLen then
				Break;

			// LKeyStart points to the opening quote of some JSON string.
			// Find the closing quote.
			LKeyEnd := FindStringEnd(LKeyStart + 1);
			if LKeyEnd < 0 then
				Break; // malformed JSON, stop scanning

			// Check if this string is followed by ':' (making it a key)
			LValStart := SkipWhitespace(LKeyEnd + 1);
			if (LValStart < LLen) and (ABytes[LValStart] = Ord(':')) then
			begin
				// This is a key. Check if it's "data".
				LIsDataKey := IsDataKey(LKeyStart + 1, LKeyEnd);

				if LIsDataKey then
				begin
					// Look at the value after the colon
					LValStart := SkipWhitespace(LValStart + 1);
					if (LValStart < LLen) and (ABytes[LValStart] = Ord('"')) then
					begin
						// It's a string value. Find its end.
						LValEnd := FindStringEnd(LValStart + 1);
						if LValEnd < 0 then
							Break; // malformed JSON

						LValLen := LValEnd - (LValStart + 1);
						if LValLen >= AThreshold then
						begin
							// Record location and replace with placeholder
							LLocation.ByteOffset := LValStart + 1;
							LLocation.ByteLength := LValLen;

							if LLocationCount >= Length(LLocations) then
								SetLength(LLocations, LLocationCount * 2);
							LLocations[LLocationCount] := LLocation;

							// Flush everything up to and including the value's opening quote
							FlushTo(LValStart + 1);
							LPos := LValStart + 1;

							// Write placeholder instead of the base64 content
							LPlaceholder := UTF8String(Format('__LAZY:%d', [LLocationCount]));
							LOut.WriteBuffer(LPlaceholder[1], Length(LPlaceholder));

							// Skip past the base64 content (LPos jumps to closing quote)
							LPos := LValEnd;

							Inc(LLocationCount);
							LKeyStart := LValEnd + 1;
							Continue;
						end;
						// Small value: skip past it normally
						LKeyStart := LValEnd + 1;
						Continue;
					end;
					// Value is not a string (number, object, etc.): skip past colon area
					LKeyStart := LValStart;
					Continue;
				end;
				// Not a "data" key: continue scanning after the colon
				LKeyStart := LValStart + 1;
				Continue;
			end;

			// Not a key (no colon follows): this string is a value or array element.
			// Continue scanning after it.
			LKeyStart := LKeyEnd + 1;
		end;

		// Flush remaining bytes
		FlushTo(LLen);

		// Build result
		SetLength(LLocations, LLocationCount);
		Result.Locations := LLocations;

		// Copy output bytes directly (no UTF-8 string conversion)
		SetLength(Result.StrippedJsonBytes, LOut.Position);
		if LOut.Position > 0 then
			Move(LOut.Memory^, Result.StrippedJsonBytes[0], LOut.Position);

	finally
		LOut.Free;
	end;
end;

function LoadBase64FromFile(const AFilePath: string; const ALocation: TBase64Location): string;
var
	LStream: TFileStream;
	LBytes: TBytes;
begin
	if not FileExists(AFilePath) then
		raise ELazyLoadError.CreateFmt('Lazy load failed: file not found: %s', [AFilePath]);

	try
		LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
		try
			if ALocation.ByteOffset + ALocation.ByteLength > LStream.Size then
				raise ELazyLoadError.CreateFmt('Lazy load failed: offset %d + length %d exceeds file size %d', [ALocation.ByteOffset, ALocation.ByteLength, LStream.Size]);

			LStream.Position := ALocation.ByteOffset;
			SetLength(LBytes, ALocation.ByteLength);
			if ALocation.ByteLength > 0 then
				LStream.ReadBuffer(LBytes[0], ALocation.ByteLength);
			Result := TEncoding.UTF8.GetString(LBytes);
		finally
			LStream.Free;
		end;
	except
		on E: ELazyLoadError do
			raise; // re-raise our own errors as-is
		on E: Exception do
			raise ELazyLoadError.CreateFmt('Lazy load failed for %s: %s', [AFilePath, E.Message]);
	end;
end;

end.
