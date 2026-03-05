/// <summary>
///   Shared utility functions for all conversation formatters.
///   Provides UTF-8 stream writing helpers and HTML escaping.
/// </summary>
unit GeminiFile.Formatter.Utils;

interface

uses
	System.SysUtils,
	System.Classes;

const
	/// <summary>Windows-style line ending used by all formatters.</summary>
	CRLF = #13#10;

	/// <summary>
	///   Writes a UTF-8 encoded string directly to the stream.
	/// </summary>
procedure StreamWrite(AStream: TStream; const AStr: string);

/// <summary>
///   Writes a UTF-8 encoded string followed by CRLF to the stream.
/// </summary>
procedure StreamWriteLn(AStream: TStream; const AStr: string = '');

/// <summary>
///   Replaces &amp; &lt; &gt; &quot; for safe HTML embedding.
/// </summary>
function HtmlEscape(const AStr: string): string;

/// <summary>
///   Builds the parenthetical suffix for thinking group summaries.
///   Returns e.g. ' (2024-01-15 12:00:00, with attachment)' or ''.
/// </summary>
/// <param name="ACreateTime">First non-zero timestamp in the group.</param>
/// <param name="AAnyResource">Whether the group contains an embedded resource.</param>
function ThinkingSummarySuffix(ACreateTime: TDateTime; AAnyResource: Boolean): string;

implementation

uses
	GeminiFile.Types;

procedure StreamWrite(AStream: TStream; const AStr: string);
var
	LBytes: TBytes;
begin
	LBytes := TEncoding.UTF8.GetBytes(AStr);
	if Length(LBytes) > 0 then
		AStream.WriteBuffer(LBytes[0], Length(LBytes));
end;

const
	/// <summary>Pre-encoded CRLF bytes to avoid per-call encoding overhead.</summary>
	CRLF_BYTES: array[0..1] of Byte = (13, 10);

procedure StreamWriteLn(AStream: TStream; const AStr: string);
begin
	StreamWrite(AStream, AStr);
	AStream.WriteBuffer(CRLF_BYTES[0], 2);
end;

function ThinkingSummarySuffix(ACreateTime: TDateTime; AAnyResource: Boolean): string;
begin
	if (ACreateTime > 0) and AAnyResource then
		Result := ' (' + FormatCreateTime(ACreateTime) + ', with attachment)'
	else if ACreateTime > 0 then
		Result := ' (' + FormatCreateTime(ACreateTime) + ')'
	else if AAnyResource then
		Result := ' (with attachment)'
	else
		Result := '';
end;

function HtmlEscape(const AStr: string): string;
var
	LSB: TStringBuilder;
	I, LRunStart: Integer;
	LNeedsEscape: Boolean;
begin
	if AStr = '' then
		Exit('');

	// Fast path: scan for special chars; return original string if none found
	LNeedsEscape := False;
	for I := 1 to Length(AStr) do
		case AStr[I] of
			'&', '<', '>', '"':
			begin
				LNeedsEscape := True;
				Break;
			end;
		end;
	if not LNeedsEscape then
		Exit(AStr);

	// Batch-append runs of non-special characters to minimize Append calls
	LSB := TStringBuilder.Create(Length(AStr) + Length(AStr) div 8);
	try
		LRunStart := 1;
		for I := 1 to Length(AStr) do
		begin
			case AStr[I] of
				'&', '<', '>', '"':
				begin
					if I > LRunStart then
						LSB.Append(AStr, LRunStart - 1, I - LRunStart);
					case AStr[I] of
						'&': LSB.Append('&amp;');
						'<': LSB.Append('&lt;');
						'>': LSB.Append('&gt;');
						'"': LSB.Append('&quot;');
					end;
					LRunStart := I + 1;
				end;
			end;
		end;
		if LRunStart <= Length(AStr) then
			LSB.Append(AStr, LRunStart - 1, Length(AStr) - LRunStart + 1);
		Result := LSB.ToString;
	finally
		LSB.Free;
	end;
end;

end.
