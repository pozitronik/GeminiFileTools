/// <summary>
///   Unit tests for the Markdown-to-HTML converter.
///   Covers headings, inline formatting, code blocks, paragraph handling,
///   and edge cases.
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
		[Test]
		procedure UnclosedInlineCode_BacktickPassesThrough;
		[Test]
		procedure PureCR_NormalizedToLF;
		[Test]
		procedure Heading1_H1Tag;
		[Test]
		procedure Heading2_H2Tag;
		[Test]
		procedure Heading3_H3Tag;
		[Test]
		procedure Heading6_H6Tag;
		[Test]
		procedure HeadingWithInlineFormatting_FormattingApplied;
		[Test]
		procedure HeadingNoSpaceAfterHash_TreatedAsProse;
		[Test]
		procedure HeadingSevenHashes_TreatedAsProse;
		[Test]
		procedure HeadingBetweenParagraphs_FlushesProseCorrectly;
		[Test]
		procedure HeadingBeforeCodeBlock_BothRendered;
		[Test]
		procedure MultipleHeadings_AllRendered;
		[Test]
		procedure HeadingWithLeadingWhitespace_StillDetected;
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

procedure TTestMarkdownToHtml.UnclosedInlineCode_BacktickPassesThrough;
var
	LResult: string;
begin
	// A lone opening backtick without a closing one should pass through literally
	LResult := MarkdownToHtml('Use `printf here');
	Assert.Contains(LResult, '`printf here');
	Assert.IsFalse(LResult.Contains('<code>'), 'Unclosed backtick must not produce code tag');
end;

procedure TTestMarkdownToHtml.PureCR_NormalizedToLF;
var
	LResult: string;
begin
	// Old Mac CR-only line endings should be normalized and treated as line breaks
	LResult := MarkdownToHtml('Line one' + #13 + 'Line two');
	Assert.Contains(LResult, 'Line one<br>Line two');
end;

procedure TTestMarkdownToHtml.Heading1_H1Tag;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('# Main Title');
	Assert.AreEqual('<h1>Main Title</h1>', LResult);
end;

procedure TTestMarkdownToHtml.Heading2_H2Tag;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('## Section');
	Assert.AreEqual('<h2>Section</h2>', LResult);
end;

procedure TTestMarkdownToHtml.Heading3_H3Tag;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('### Subsection');
	Assert.AreEqual('<h3>Subsection</h3>', LResult);
end;

procedure TTestMarkdownToHtml.Heading6_H6Tag;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('###### Deepest');
	Assert.AreEqual('<h6>Deepest</h6>', LResult);
end;

procedure TTestMarkdownToHtml.HeadingWithInlineFormatting_FormattingApplied;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('## **Bold** and `code` heading');
	Assert.Contains(LResult, '<h2>');
	Assert.Contains(LResult, '<strong>Bold</strong>');
	Assert.Contains(LResult, '<code>code</code>');
	Assert.Contains(LResult, '</h2>');
end;

procedure TTestMarkdownToHtml.HeadingNoSpaceAfterHash_TreatedAsProse;
var
	LResult: string;
begin
	// '#word' without a space after # is not a heading
	LResult := MarkdownToHtml('#hashtag');
	Assert.IsFalse(LResult.Contains('<h1>'), 'No space after # should not produce heading');
	Assert.Contains(LResult, '#hashtag');
end;

procedure TTestMarkdownToHtml.HeadingSevenHashes_TreatedAsProse;
var
	LResult: string;
begin
	// ####### (7 hashes) exceeds h6, should be prose
	LResult := MarkdownToHtml('####### Not a heading');
	Assert.IsFalse(LResult.Contains('<h7>'), 'Seven hashes should not produce heading');
	Assert.Contains(LResult, '####### Not a heading');
end;

procedure TTestMarkdownToHtml.HeadingBetweenParagraphs_FlushesProseCorrectly;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('Before text' + #10 + '## Heading' + #10 + 'After text');
	Assert.Contains(LResult, '<p>Before text</p>');
	Assert.Contains(LResult, '<h2>Heading</h2>');
	Assert.Contains(LResult, '<p>After text</p>');
end;

procedure TTestMarkdownToHtml.HeadingBeforeCodeBlock_BothRendered;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('## Example' + #10 + '```' + #10 + 'code' + #10 + '```');
	Assert.Contains(LResult, '<h2>Example</h2>');
	Assert.Contains(LResult, '<pre><code>code</code></pre>');
end;

procedure TTestMarkdownToHtml.MultipleHeadings_AllRendered;
var
	LResult: string;
begin
	LResult := MarkdownToHtml('# Title' + #10 + 'Intro' + #10 + '## Part 1' + #10 + 'Text' + #10 + '## Part 2');
	Assert.Contains(LResult, '<h1>Title</h1>');
	Assert.Contains(LResult, '<h2>Part 1</h2>');
	Assert.Contains(LResult, '<h2>Part 2</h2>');
	Assert.Contains(LResult, '<p>Intro</p>');
	Assert.Contains(LResult, '<p>Text</p>');
end;

procedure TTestMarkdownToHtml.HeadingWithLeadingWhitespace_StillDetected;
var
	LResult: string;
begin
	// Leading spaces should not prevent heading detection
	LResult := MarkdownToHtml('  ## Indented Heading');
	Assert.Contains(LResult, '<h2>Indented Heading</h2>');
end;

initialization
	TDUnitX.RegisterTestFixture(TTestMarkdownToHtml);

end.
