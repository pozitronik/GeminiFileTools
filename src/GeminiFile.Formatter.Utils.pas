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

procedure StreamWriteLn(AStream: TStream; const AStr: string);
begin
	StreamWrite(AStream, AStr + CRLF);
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
	I: Integer;
	LCh: Char;
begin
	if AStr = '' then
		Exit('');

	LSB := TStringBuilder.Create(Length(AStr) + Length(AStr) div 8);
	try
		for I := 1 to Length(AStr) do
		begin
			LCh := AStr[I];
			case LCh of
				'&':
					LSB.Append('&amp;');
				'<':
					LSB.Append('&lt;');
				'>':
					LSB.Append('&gt;');
				'"':
					LSB.Append('&quot;');
				else
					LSB.Append(LCh);
			end;
		end;
		Result := LSB.ToString;
	finally
		LSB.Free;
	end;
end;

end.
