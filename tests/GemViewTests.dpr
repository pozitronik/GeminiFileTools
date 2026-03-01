/// <summary>
///   DUnitX test runner for the GeminiFile library.
///   Console runner with NUnit XML output for CI compatibility.
/// </summary>
program GemViewTests;

{$APPTYPE CONSOLE}

{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  GeminiFile.Types in '..\src\GeminiFile.Types.pas',
  GeminiFile.Model in '..\src\GeminiFile.Model.pas',
  GeminiFile.Parser in '..\src\GeminiFile.Parser.pas',
  GeminiFile.Extractor in '..\src\GeminiFile.Extractor.pas',
  GeminiFile.LazyData in '..\src\GeminiFile.LazyData.pas',
  GeminiFile in '..\src\GeminiFile.pas',
  GeminiFile.Formatter.Intf in '..\src\GeminiFile.Formatter.Intf.pas',
  GeminiFile.Formatter.Utils in '..\src\GeminiFile.Formatter.Utils.pas',
  GeminiFile.Formatter.Text in '..\src\GeminiFile.Formatter.Text.pas',
  GeminiFile.Formatter.Md in '..\src\GeminiFile.Formatter.Md.pas',
  GeminiFile.Formatter.Html in '..\src\GeminiFile.Formatter.Html.pas',
  GeminiFile.Markdown in '..\src\GeminiFile.Markdown.pas',
  GeminiFile.Grouping in '..\src\GeminiFile.Grouping.pas',
  WcxApi in '..\wcx\WcxApi.pas',
  GeminiWcx in '..\wcx\GeminiWcx.pas',
  Tests.GeminiFile.Types in 'Tests.GeminiFile.Types.pas',
  Tests.GeminiFile.Resource in 'Tests.GeminiFile.Resource.pas',
  Tests.GeminiFile.Chunk in 'Tests.GeminiFile.Chunk.pas',
  Tests.GeminiFile.Parser in 'Tests.GeminiFile.Parser.pas',
  Tests.GeminiFile.Extractor in 'Tests.GeminiFile.Extractor.pas',
  Tests.GeminiFile.Integration in 'Tests.GeminiFile.Integration.pas',
  Tests.GeminiFile.Formatter in 'Tests.GeminiFile.Formatter.pas',
  Tests.GeminiFile.Markdown in 'Tests.GeminiFile.Markdown.pas',
  Tests.GeminiWcx in 'Tests.GeminiWcx.pas',
  Tests.GeminiFile.Grouping in 'Tests.GeminiFile.Grouping.pas',
  Tests.GeminiFile.LazyData in 'Tests.GeminiFile.LazyData.pas',
  Tests.GeminiFile.TestUtils in 'Tests.GeminiFile.TestUtils.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNUnitLogger: ITestLogger;
begin
  try
    TDUnitX.CheckCommandLine;
    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    LRunner.FailsOnNoAsserts := False;

    LLogger := TDUnitXConsoleLogger.Create(True);
    LRunner.AddLogger(LLogger);

    LNUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNUnitLogger);

    LResults := LRunner.Execute;
    if not LResults.AllPassed then
      ExitCode := 1;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      Write('Press Enter to continue...');
      ReadLn;
    end;
    {$ENDIF}
  except
    on E: Exception do
    begin
      WriteLn('Fatal: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
