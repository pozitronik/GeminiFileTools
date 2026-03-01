/// <summary>
///   Unit tests for the Markdown-to-HTML converter.
///   Covers inline formatting, code blocks, paragraph handling, and edge cases.
/// </summary>
unit Tests.GeminiFile.Markdown;

interface

uses
	System.SysUtils,
	DUnitX.TestFramework,
	GeminiFile.Markdown;

type
	[TestFixture]
	TTestMarkdownToHtml = class
	public
		[Test]
		procedure EmptyInput_ReturnsEmpty;
		[Test]
		procedure PlainText_WrappedInParagraph;
		[Test]
		procedure BoldText_StrongTags;
		[Test]
		procedure ItalicText_EmTags;
		[Test]
		procedure BoldItalicCombined_NestedTags;
		[Test]
		procedure InlineCode_CodeTags;
		[Test]
		procedure Strikethrough_DelTags;
		[Test]
		procedure FencedCodeBlock_PreCodeTags;
		[Test]
		procedure FencedCodeBlockWithLanguage_HasClass;
		[Test]
		procedure HtmlSpecialChars_Escaped;
		[Test]
		procedure InlineCodeContent_NotProcessed;
		[Test]
		procedure CodeBlockContent_NotProcessed;
		[Test]
		procedure MultipleParagraphs_SeparatePTags;
		[Test]
		procedure SingleNewline_BrTag;
		[Test]
		procedure UnmatchedMarker_LiteralText;
		[Test]
		procedure MixedFormatting_AllApplied;
		[Test]
		procedure ClosingMarkerWithSpaceBefore_NotApplied;
		[Test]
		procedure UnclosedCodeBlock_TreatedAsProse;
		[Test]
		procedure EmptyDelimiter_ReturnsSingleElement;
	end;

implementation

procedure TTestMarkdownToHtml.EmptyInput_ReturnsEmpty;
begin
	Assert.AreEqual('', MarkdownToHtml(''));
end;

procedure TTestMarkdownToHtml.PlainText_WrappedInParagraph;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('Hello world');
	Assert.AreEqual('<p>Hello world</p>', LResult);
end;

procedure TTestMarkdownToHtml.BoldText_StrongTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('This is **bold** text');
	Assert.Contains(LResult, '<strong>bold</strong>');
end;

procedure TTestMarkdownToHtml.ItalicText_EmTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('This is *italic* text');
	Assert.Contains(LResult, '<em>italic</em>');
end;

procedure TTestMarkdownToHtml.BoldItalicCombined_NestedTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('This is ***bold italic*** text');
	Assert.Contains(LResult, '<strong><em>bold italic</em></strong>');
end;

procedure TTestMarkdownToHtml.InlineCode_CodeTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('Use `printf()` here');
	Assert.Contains(LResult, '<code>printf()</code>');
end;

procedure TTestMarkdownToHtml.Strikethrough_DelTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('This is ~~deleted~~ text');
	Assert.Contains(LResult, '<del>deleted</del>');
end;

procedure TTestMarkdownToHtml.FencedCodeBlock_PreCodeTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('Before' + #10 + '```' + #10 + 'code here' + #10 + '```' + #10 + 'After');
	Assert.Contains(LResult, '<pre><code>code here</code></pre>');
	Assert.Contains(LResult, '<p>Before</p>');
	Assert.Contains(LResult, '<p>After</p>');
end;

procedure TTestMarkdownToHtml.FencedCodeBlockWithLanguage_HasClass;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('```python' + #10 + 'print("hello")' + #10 + '```');
	Assert.Contains(LResult, 'class="language-python"');
	Assert.Contains(LResult, 'print(&quot;hello&quot;)');
end;

procedure TTestMarkdownToHtml.HtmlSpecialChars_Escaped;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('<script>alert("xss")&</script>');
	Assert.Contains(LResult, '&lt;script&gt;');
	Assert.Contains(LResult, '&amp;');
	Assert.IsFalse(LResult.Contains('<script>'), 'HTML tags must be escaped');
end;

procedure TTestMarkdownToHtml.InlineCodeContent_NotProcessed;
var
	LResult: string;
begin
	// Markdown markers inside inline code must remain literal
	LResult := MarkdownToHtml('Use `**not bold**` here');
	Assert.Contains(LResult, '<code>**not bold**</code>');
	Assert.IsFalse(LResult.Contains('<strong>'), 'Code content must not be styled');
end;

procedure TTestMarkdownToHtml.CodeBlockContent_NotProcessed;
var
	LResult: string;
begin
	// Content inside fenced code blocks must not have inline formatting applied
	LResult := MarkdownToHtml('```' + #10 + '**not bold** *not italic*' + #10 + '```');
	Assert.Contains(LResult, '**not bold** *not italic*');
	Assert.IsFalse(LResult.Contains('<strong>'), 'Code block content must not be styled');
	Assert.IsFalse(LResult.Contains('<em>'), 'Code block content must not be styled');
end;

procedure TTestMarkdownToHtml.MultipleParagraphs_SeparatePTags;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('First paragraph' + #10 + #10 + 'Second paragraph');
	Assert.Contains(LResult, '<p>First paragraph</p>');
	Assert.Contains(LResult, '<p>Second paragraph</p>');
end;

procedure TTestMarkdownToHtml.SingleNewline_BrTag;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('Line one' + #10 + 'Line two');
	Assert.Contains(LResult, 'Line one<br>Line two');
end;

procedure TTestMarkdownToHtml.UnmatchedMarker_LiteralText;
var
	LResult: string;
begin
	// A lone asterisk in a math expression should not trigger formatting
	LResult := MarkdownToHtml('2 * 3 * 4');
	// The flanking rule prevents this from becoming italic
	Assert.IsFalse(LResult.Contains('<em>'), 'Unmatched/non-flanking markers must stay literal');
	Assert.Contains(LResult, '2 * 3 * 4');
end;

procedure TTestMarkdownToHtml.MixedFormatting_AllApplied;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('**bold** and *italic* and `code` and ~~strike~~');
	Assert.Contains(LResult, '<strong>bold</strong>');
	Assert.Contains(LResult, '<em>italic</em>');
	Assert.Contains(LResult, '<code>code</code>');
	Assert.Contains(LResult, '<del>strike</del>');
end;

procedure TTestMarkdownToHtml.ClosingMarkerWithSpaceBefore_NotApplied;
var
	LResult: string;
begin
	// Closing ** preceded by space violates the flanking rule
	LResult := MarkdownToHtml('**word ** still here');
	Assert.IsFalse(LResult.Contains('<strong>'),
		'Closing marker preceded by space should not be applied');
end;

procedure TTestMarkdownToHtml.UnclosedCodeBlock_TreatedAsProse;
var
	LResult: string;
begin
	// A ``` opener without a closer should be treated as regular prose
	LResult := MarkdownToHtml('before' + #10 + '```python' + #10 + 'code line');
	Assert.IsFalse(LResult.Contains('<pre>'),
		'Unclosed code block should not produce <pre> tag');
	// The fallback path concatenates the fence and content into prose
	Assert.Contains(LResult, 'code line');
	Assert.Contains(LResult, 'before');
end;

procedure TTestMarkdownToHtml.EmptyDelimiter_ReturnsSingleElement;
var
	LResult: string;
begin
	// Empty string input should still produce output (via ProcessProse short-circuit)
	LResult := MarkdownToHtml('   ');
	// Whitespace-only input produces an empty paragraph that gets skipped
	Assert.AreEqual('', LResult);
end;

initialization
	TDUnitX.RegisterTestFixture(TTestMarkdownToHtml);

end.
