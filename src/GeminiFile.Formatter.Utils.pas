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

implementation

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

function HtmlEscape(const AStr: string): string;
begin
	Result := AStr;
	Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
	Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
	Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
	Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

end.
