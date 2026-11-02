unit demos;

// ---------------------------------------------------------------------------
//  qtxFunctionalDemo - showcase pipelines
//
//  Each TDemos function builds a real qtxFunctional pipeline, runs it, and
//  returns an HTML card with the pipeline source and its live result.
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.lazy,
  functional.fusion,
  functional.lazyinteger,
  functional.sequence;

type
  TDemos = class
  public
    class function Welcome: String;
    class function Primes: String;
    class function Fibonacci: String;
    class function Collatz: String;
    class function Fusion: String;
    class function Laziness: String;
    class function Words: String;
  end;

implementation

const
  NL = #10;

{ Presentation helpers }

function Card(const Title, Intro, Code, Output: String): String;
const
  LabelStyle = 'font-weight:bold;font-size:11px;letter-spacing:1px;color:#8a96a3;' +
               'text-transform:uppercase;margin:0 0 4px 0';
begin
  Result :=
    '<h2 style="margin:0 0 6px 0;font-weight:500">' + Title + '</h2>' +
    '<p style="margin:0 0 16px 0;color:#555;line-height:1.55;max-width:760px">' + Intro + '</p>' +
    '<div style="' + LabelStyle + '">Pipeline</div>' +
    '<pre style="background:#1e2a3a;color:#d6e4f0;padding:14px;border-radius:6px;' +
      'margin:0 0 16px 0;overflow-x:auto;font-size:13px;line-height:1.5">' + Code + '</pre>' +
    '<div style="' + LabelStyle + '">Result</div>' +
    '<pre style="background:#eef3f8;color:#1e2a3a;padding:14px;border-radius:6px;' +
      'margin:0;white-space:pre-wrap;font-size:13px;line-height:1.6">' + Output + '</pre>';
end;

function Row(const Name, Value: String): String;
begin
  Result := Name + ' : ' + Value + NL;
end;

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

{ Reusable functions for the demos }

function PrimeTest: TIntPredicate;
begin
  Result := function (Value: Integer): Boolean
    var
      d: Integer;
    begin
      if Value < 2 then
        exit(False);
      d := 2;
      while d * d <= Value do
      begin
        if (Value mod d) = 0 then
          exit(False);
        Inc(d);
      end;
      Result := True;
    end;
end;

function Fib: TIntFunc;
begin
  Result := function (Value: Integer): Integer
    var
      a, b, t, i: Integer;
    begin
      a := 0;
      b := 1;
      for i := 1 to Value do
      begin
        t := a + b;
        a := b;
        b := t;
      end;
      Result := a;
    end;
end;

function Below(Limit: Integer): TVarPredicate;
var
  Bound: Integer;
begin
  Bound := Limit;
  Result := function (Value: Variant): Boolean
    var
      N: Integer;
    begin
      N := Value;
      Result := N < Bound;
    end;
end;

function CollatzStep: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    var
      N: Integer;
    begin
      N := Value;
      if (N mod 2) = 0 then
        Result := N div 2
      else
        Result := 3 * N + 1;
    end;
end;

function NotOne: TVarPredicate;
begin
  Result := function (Value: Variant): Boolean
    var
      N: Integer;
    begin
      N := Value;
      Result := N <> 1;
    end;
end;

function LongerThan(Size: Integer): TVarPredicate;
var
  Limit: Integer;
begin
  Limit := Size;
  Result := function (Value: Variant): Boolean
    var
      S: String;
    begin
      S := Value;
      Result := Length(S) > Limit;
    end;
end;

function ToUpper: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    var
      S: String;
    begin
      S := Value;
      Result := UpperCase(S);
    end;
end;

{ TDemos }

class function TDemos.Welcome: String;
begin
  Result :=
    '<h2 style="margin:0 0 10px 0;font-weight:500">A functional toolkit for Quartex Pascal</h2>' +
    '<p style="color:#555;line-height:1.6;max-width:760px;margin:0 0 14px 0">' +
    'qtxFunctional brings ideas from Haskell (by way of Hackage''s Friday library) to ' +
    'Object Pascal: <b>higher-order functions</b>, <b>lazy evaluation</b>, <b>function ' +
    'composition</b>, <b>stream fusion</b> and <b>immutable data</b>. Every result on these ' +
    'pages is computed live in your browser by pipelines written in plain Pascal - no ' +
    'inline JavaScript.</p>' +
    '<table style="border-collapse:collapse;font-size:14px;line-height:1.5">' +
    '<tr><td style="padding:6px 18px 6px 0"><b>TFunction</b></td><td style="color:#555">Higher-order function factories, composition, partial application</td></tr>' +
    '<tr><td style="padding:6px 18px 6px 0"><b>TLazy</b></td><td style="color:#555">Deferred, memoised values with Map and Bind</td></tr>' +
    '<tr><td style="padding:6px 18px 6px 0"><b>TSequence</b></td><td style="color:#555">General-purpose lazy, immutable streams of any value type</td></tr>' +
    '<tr><td style="padding:6px 18px 6px 0"><b>TFusion</b></td><td style="color:#555">The engine that merges pipeline stages and runs them in one pass</td></tr>' +
    '<tr><td style="padding:6px 18px 6px 0"><b>TLazyInteger</b></td><td style="color:#555">A typed integer stream: Map, Filter, Take, Fold</td></tr>' +
    '</table>' +
    '<p style="color:#555;margin:16px 0 0 0">Pick a demo from the toolbar above.</p>';
end;

class function TDemos.Primes: String;
var
  First20, Hundred: TLazyInteger;
  Output: String;
begin
  First20 := TLazyInteger.From(2).Filter(PrimeTest()).Take(20);
  Hundred := TLazyInteger.From(2).Filter(PrimeTest()).Take(100);

  Output :=
    Row('First 20 primes      ', First20.AsString) +
    Row('Sum of first 100     ', IntToStr(Hundred.Fold(0, TFunction.Sum()))) +
    Row('100th prime (Maximum)', IntToStr(Hundred.Fold(0, TFunction.Maximum())));

  Result := Card('Primes from an infinite stream',
    'TLazyInteger.From(2) describes every integer from 2 upwards - an infinite stream. ' +
    'Because Filter and Take are lazy, only as many numbers are examined as are needed ' +
    'to find the requested primes. The same Filter feeds both a list and two Folds.',
    'var Primes := TLazyInteger.From(2)' + NL +
    '                .Filter(PrimeTest)' + NL +
    '                .Take(20);' + NL + NL +
    'Primes.AsString;' + NL +
    'TLazyInteger.From(2).Filter(PrimeTest).Take(100)' + NL +
    '  .Fold(0, TFunction.Sum);',
    Output);
end;

class function TDemos.Fibonacci: String;
var
  Fibs, EvenFibs: TSequence;
  Output: String;
begin
  Fibs := TSequence.From(0).Map(TVarFunction.Lift(Fib())).Take(15);

  EvenFibs := TSequence.From(0)
    .Map(TVarFunction.Lift(Fib()))
    .TakeWhile(Below(4000000))
    .Filter(TVarFunction.LiftPredicate(TFunction.IsEven()));

  Output :=
    Row('First 15 Fibonacci numbers', Fibs.AsString) +
    Row('Even terms below 4,000,000', EvenFibs.AsString) +
    Row('Their sum                 ', VarText(EvenFibs.Fold(0,
      TVarFunction.LiftFold(TFunction.Sum())))) +
    Row('Fused plan                ', EvenFibs.Describe);

  Result := Card('Fibonacci with TakeWhile',
    'An integer function is lifted into a Variant pipeline with TVarFunction.Lift. ' +
    'TakeWhile stops an infinite stream as soon as its condition fails - here it ' +
    'solves Project Euler problem 2 without ever choosing an upper index.',
    'var EvenFibs := TSequence.From(0)' + NL +
    '  .Map(TVarFunction.Lift(Fib))' + NL +
    '  .TakeWhile(Below(4000000))' + NL +
    '  .Filter(TVarFunction.LiftPredicate(TFunction.IsEven));' + NL + NL +
    'EvenFibs.Fold(0, TVarFunction.LiftFold(TFunction.Sum));',
    Output);
end;

class function TDemos.Collatz: String;
var
  Path: TSequence;
  Output: String;
begin
  Path := TSequence.Iterate(27, CollatzStep()).TakeWhile(NotOne());

  Output :=
    Row('First 15 values ', Path.Take(15).AsString) +
    Row('Steps to reach 1', IntToStr(Path.Count)) +
    Row('Highest value   ', VarText(Path.Fold(0,
      TVarFunction.LiftFold(TFunction.Maximum()))));

  Result := Card('The Collatz sequence from 27',
    'TSequence.Iterate(seed, f) produces seed, f(seed), f(f(seed)), ... forever. ' +
    'The same immutable Path is reused three times - each run restarts the generator ' +
    'from 27, and deriving Path.Take(15) leaves Path itself untouched.',
    'var Path := TSequence.Iterate(27, CollatzStep)' + NL +
    '              .TakeWhile(NotOne);' + NL + NL +
    'Path.Take(15).AsString;' + NL +
    'Path.Count;' + NL +
    'Path.Fold(0, TVarFunction.LiftFold(TFunction.Maximum));',
    Output);
end;

class function TDemos.Fusion: String;
var
  Pulled: Integer;
  Spy: TVarFunc;
  Pipe: TSequence;
  Values, Output: String;
begin
  Pulled := 0;
  Spy := function (Value: Variant): Variant
    begin
      Inc(Pulled);
      Result := Value;
    end;

  Pipe := TSequence.From(1)
    .Map(Spy)
    .Map(TVarFunction.Lift(TFunction.Square()))
    .Map(TVarFunction.Lift(TFunction.Add(1)))
    .Filter(TVarFunction.LiftPredicate(TFunction.IsOdd()))
    .Filter(TVarFunction.LiftPredicate(TFunction.GreaterThan(10)))
    .Take(10)
    .Take(5);

  Values := Pipe.AsString;

  Output :=
    Row('Calls written          ', '7 transformations') +
    Row('Stages after fusion    ', IntToStr(Pipe.StageCount)) +
    Row('Fused plan             ', Pipe.Describe) +
    Row('Values                 ', Values) +
    Row('Source elements pulled ', IntToStr(Pulled) + ' (from an infinite source)') +
    Row('Intermediate arrays    ', 'none - one pass straight into the result');

  Result := Card('Stream fusion',
    'TFusion rewrites adjacent stages as the pipeline is built: three Maps become one ' +
    'composed function, two Filters become one combined test, and two Takes become the ' +
    'smaller one. At run time every stage is chained into a single function, and the ' +
    'source stops the moment the last value is delivered.',
    'TSequence.From(1)' + NL +
    '  .Map(Spy)                     // counts pulled elements' + NL +
    '  .Map(Lift(TFunction.Square))' + NL +
    '  .Map(Lift(TFunction.Add(1)))' + NL +
    '  .Filter(LiftPredicate(TFunction.IsOdd))' + NL +
    '  .Filter(LiftPredicate(TFunction.GreaterThan(10)))' + NL +
    '  .Take(10)' + NL +
    '  .Take(5);',
    Output);
end;

class function TDemos.Laziness: String;
var
  Runs: Integer;
  Total, Doubled, Prime1000: TLazy;
  Before, Output: String;
begin
  Runs := 0;
  Total := TLazy.Create(
    function: Variant
    begin
      Inc(Runs);
      Result := TSequence.Range(1, 1000000)
        .Fold(0, TVarFunction.LiftFold(TFunction.Sum()));
    end);
  Doubled := Total.Map(TVarFunction.Lift(TFunction.Multiply(2)));
  Before := BoolToStr(Total.IsEvaluated);

  Output :=
    Row('Total.IsEvaluated before any read', Before) +
    Row('Doubled.Value                    ', VarText(Doubled.Value)) +
    Row('Total.Value                      ', VarText(Total.Value)) +
    Row('Total.Value (again)              ', VarText(Total.Value)) +
    Row('Times the sum was computed       ', IntToStr(Runs));

  Prime1000 := TSequence.From(2)
    .Filter(TVarFunction.LiftPredicate(PrimeTest()))
    .Drop(999)
    .Head;
  Output := Output + NL +
    Row('Prime1000.IsEvaluated            ', BoolToStr(Prime1000.IsEvaluated)) +
    Row('Prime1000.Value                  ', VarText(Prime1000.Value));

  Result := Card('Lazy, memoised values',
    'A TLazy holds a computation, not a result. Mapping over it builds a new lazy ' +
    'without running anything. The million-element sum runs once, on first demand, and ' +
    'is cached for every later read. Head turns "the 1000th prime" into a value that ' +
    'is only found when asked for.',
    'var Total := TLazy.Create(function: Variant' + NL +
    '  begin' + NL +
    '    Result := TSequence.Range(1, 1000000)' + NL +
    '      .Fold(0, TVarFunction.LiftFold(TFunction.Sum));' + NL +
    '  end);' + NL +
    'var Doubled := Total.Map(Lift(TFunction.Multiply(2)));' + NL + NL +
    'var Prime1000 := TSequence.From(2)' + NL +
    '  .Filter(LiftPredicate(PrimeTest)).Drop(999).Head;',
    Output);
end;

class function TDemos.Words: String;
var
  Source: TVarArray;
  Base, Long, Short: TSequence;
  Output: String;
begin
  Source := ['functional', 'programming', 'in', 'quartex', 'pascal', 'is',
             'lazy', 'composable', 'and', 'immutable'];
  Base := TSequence.FromArray(Source);

  Long := Base.Filter(LongerThan(4)).Map(ToUpper());
  Short := Base.Filter(TVarFunction.Negate(LongerThan(4)));

  Output :=
    Row('Long words, upper-cased', VarText(Long.Fold('', TVarFunction.Concat(' '))))  +
    Row('Short words            ', VarText(Short.Fold('', TVarFunction.Concat(', ')))) +
    Row('Base still holds       ', IntToStr(Base.Count) + ' words: ' + Base.AsString);

  Result := Card('Branching an immutable pipeline',
    'TSequence carries any value type. Here one Base sequence of strings is branched ' +
    'into two independent pipelines. Neither branch changes Base, so it can be reused ' +
    'freely - immutability makes sharing safe.',
    'var Base  := TSequence.FromArray(Words);' + NL +
    'var Long  := Base.Filter(LongerThan(4)).Map(ToUpper);' + NL +
    'var Short := Base.Filter(TVarFunction.Negate(LongerThan(4)));' + NL + NL +
    'Long.Fold('''', TVarFunction.Concat('' ''));',
    Output);
end;

end.
