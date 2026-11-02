unit app.body;

interface

uses
  qtx.sysutils,
  qtx.classes,
  qtx.components,
  qtx.node.console,
  qtx.node.application,
  functional.functions,
  functional.lazy,
  functional.fusion,
  functional.lazyinteger,
  functional.sequence,
  functional.stats,
  functional.eager,
  functional.floats,
  functional.fn,
  functional.lazylist,
  functional.collections,
  tests.roadmap,
  functional.vector,
  functional.fft,
  functional.automata,
  functional.neural,
  conventional.numeric,
  tests.stage6,
  tests.extensions;

type

  TNodeApplication = class(TQTXNodeApplication)
  private
    FPassed: Integer;
    FFailed: Integer;
    procedure Check(const Name, Actual, Expected: String);
    procedure Section(const Title: String);
    procedure TestLazyInteger;
    procedure TestLazy;
    procedure TestSequence;
    procedure TestFusion;
  public
    procedure DoExecute; override;
  end;

implementation

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

{ Harness }

procedure TNodeApplication.Check(const Name, Actual, Expected: String);
begin
  if Actual = Expected then
  begin
    Inc(FPassed);
    writeln('  PASS  ' + Name + ' = ' + Actual);
  end
  else
  begin
    Inc(FFailed);
    writeln('  FAIL  ' + Name + ': got ' + Actual + ', expected ' + Expected);
  end;
end;

procedure TNodeApplication.Section(const Title: String);
begin
  writeln('');
  writeln(Title);
end;

{ TLazyInteger }

procedure TNodeApplication.TestLazyInteger;
var
  Calls: Integer;
  Spy: TIntFunc;
  Base, Doubled, Pipeline, Fused: TLazyInteger;
  Source: TIntArray;
  Snapshot: TLazyInteger;
begin
  Section('TLazyInteger - Map, Filter, Take, Fold');
  Pipeline := TLazyInteger.Range(1, 10)
    .Map(TFunction.Square())
    .Filter(TFunction.IsEven())
    .Take(3);
  Check('Range(1,10).Map(sqr).Filter(even).Take(3)', Pipeline.AsString, '[4, 16, 36]');
  Check('  ...Fold(0, Sum)', IntToStr(Pipeline.Fold(0, TFunction.Sum())), '56');
  Check('Range(1,5).Fold(1, Product)',
    IntToStr(TLazyInteger.Range(1, 5).Fold(1, TFunction.Product())), '120');
  Check('Range(1,10).Take(4).Filter(even)  (stage order respected)',
    TLazyInteger.Range(1, 10).Take(4).Filter(TFunction.IsEven()).AsString, '[2, 4]');

  Section('TLazyInteger - laziness');
  Check('From(1).Filter(odd).Map(*3).Take(5)',
    TLazyInteger.From(1)
      .Filter(TFunction.IsOdd())
      .Map(TFunction.Multiply(3))
      .Take(5).AsString,
    '[3, 9, 15, 21, 27]');

  Calls := 0;
  Spy := function (Value: Integer): Integer
    begin
      Inc(Calls);
      Result := Value * 10;
    end;
  Pipeline := TLazyInteger.From(1).Map(Spy).Take(3);
  Check('Map calls before terminal op', IntToStr(Calls), '0');
  Check('From(1).Map(spy).Take(3)', Pipeline.AsString, '[10, 20, 30]');
  Check('Map calls after terminal op', IntToStr(Calls), '3');

  try
    TLazyInteger.From(1).Map(TFunction.Square()).Fold(0, TFunction.Sum());
    Check('Unbounded infinite fold rejected', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('Unbounded infinite fold rejected', 'EFunctional', 'EFunctional');
  end;

  Section('TLazyInteger - composition, fusion, immutability');
  Check('Compose(+1, *2)(5)  = (5*2)+1',
    IntToStr(TFunction.Compose(TFunction.Add(1), TFunction.Multiply(2))(5)), '11');
  Check('AndThen(+1, *2)(5)  = (5+1)*2',
    IntToStr(TFunction.AndThen(TFunction.Add(1), TFunction.Multiply(2))(5)), '12');

  Fused := TLazyInteger.Range(1, 5)
    .Map(TFunction.Add(1))
    .Map(TFunction.Multiply(2))
    .Map(TFunction.Add(-3));
  Check('3 Maps fuse into stages', IntToStr(Fused.StageCount), '1');
  Check('  ...values', Fused.AsString, '[1, 3, 5, 7, 9]');

  Base := TLazyInteger.Range(1, 5);
  Doubled := Base.Map(TFunction.Multiply(2));
  Check('Base unchanged after Map', Base.AsString, '[1, 2, 3, 4, 5]');
  Check('Derived stream', Doubled.AsString, '[2, 4, 6, 8, 10]');

  Source := [7, 8, 9];
  Snapshot := TLazyInteger.FromArray(Source);
  Source[0] := 100;
  Check('FromArray takes a defensive copy', Snapshot.AsString, '[7, 8, 9]');
end;

{ TLazy }

procedure TNodeApplication.TestLazy;
var
  Calls: Integer;
  Answer, Bigger, Chained: TLazy;
begin
  Section('TLazy - deferred, memoised values');
  Calls := 0;
  Answer := TLazy.Create(
    function: Variant
    begin
      Inc(Calls);
      Result := 21;
    end);
  Check('Not evaluated on creation', BoolToStr(Answer.IsEvaluated), BoolToStr(False));
  Check('Thunk calls before .Value', IntToStr(Calls), '0');

  Bigger := Answer.Map(TVarFunction.Lift(TFunction.Multiply(2)));
  Check('Map does not force the source', BoolToStr(Answer.IsEvaluated), BoolToStr(False));
  Check('Mapped value', VarText(Bigger.Value), '42');
  Check('Source forced by mapped read', BoolToStr(Answer.IsEvaluated), BoolToStr(True));

  VarText(Answer.Value);
  VarText(Answer.Value);
  Check('Thunk runs once (memoised)', IntToStr(Calls), '1');

  Check('Pure is already evaluated', BoolToStr(TLazy.Pure(7).IsEvaluated), BoolToStr(True));

  Chained := TLazy.Pure(5).Bind(
    function (Value: Variant): TLazy
    var
      N: Integer;
    begin
      N := Value;
      Result := TLazy.Pure(N * N);
    end);
  Check('Pure(5).Bind(x -> Pure(x*x))', VarText(Chained.Value), '25');
end;

{ TSequence }

procedure TNodeApplication.TestSequence;
var
  Calls: Integer;
  Spy, Collatz, Label: TVarFunc;
  NotOne: TVarPredicate;
  Powers: TSequence;
  Total, First: TLazy;
  Words: TVarArray;
begin
  Section('TSequence - general-purpose lazy streams');
  Check('Range(1,10).Map(sqr).Filter(even).Take(3)',
    TSequence.Range(1, 10)
      .Map(TVarFunction.Lift(TFunction.Square()))
      .Filter(TVarFunction.LiftPredicate(TFunction.IsEven()))
      .Take(3).AsString,
    '[4, 16, 36]');

  Powers := TSequence.Iterate(1, TVarFunction.Lift(TFunction.Multiply(2))).Take(10);
  Check('Iterate(1, *2).Take(10)', Powers.AsString,
    '[1, 2, 4, 8, 16, 32, 64, 128, 256, 512]');
  Check('  ...re-run restarts the generator', VarText(Powers.Fold(0,
    TVarFunction.LiftFold(TFunction.Sum()))), '1023');

  Collatz := function (Value: Variant): Variant
    var
      N: Integer;
    begin
      N := Value;
      if (N mod 2) = 0 then
        Result := N div 2
      else
        Result := 3 * N + 1;
    end;
  NotOne := function (Value: Variant): Boolean
    var
      N: Integer;
    begin
      N := Value;
      Result := N <> 1;
    end;
  Check('Iterate(6, collatz).TakeWhile(<>1)',
    TSequence.Iterate(6, Collatz).TakeWhile(NotOne).AsString,
    '[6, 3, 10, 5, 16, 8, 4, 2]');

  Check('From(1).Drop(5).Drop(5).Take(3)',
    TSequence.From(1).Drop(5).Drop(5).Take(3).AsString, '[11, 12, 13]');
  Check('Replicate(''ab'', 3).Count', IntToStr(TSequence.Replicate('ab', 3).Count), '3');

  Section('TSequence - mixed value types');
  Label := function (Value: Variant): Variant
    var
      N: Integer;
    begin
      N := Value;
      Result := 'item' + IntToStr(N);
    end;
  Check('Range(1,3).Map(int->string).Fold(Concat)',
    VarText(TSequence.Range(1, 3).Map(Label).Fold('', TVarFunction.Concat(', '))),
    'item1, item2, item3');

  Words := ['alpha', 'beta', 'gamma'];
  Check('FromArray(strings).Drop(1).Fold(Concat)',
    VarText(TSequence.FromArray(Words).Drop(1).Fold('', TVarFunction.Concat('-'))),
    'beta-gamma');

  Section('TSequence - deferred terminals return TLazy');
  Total := TSequence.Range(1, 100).FoldLazy(0, TVarFunction.LiftFold(TFunction.Sum()));
  Check('FoldLazy not run yet', BoolToStr(Total.IsEvaluated), BoolToStr(False));
  Check('FoldLazy(Sum) over 1..100', VarText(Total.Value), '5050');

  Calls := 0;
  Spy := function (Value: Variant): Variant
    var
      N: Integer;
    begin
      Inc(Calls);
      N := Value;
      Result := N * 10;
    end;
  First := TSequence.From(1).Map(Spy).Head;
  Check('Head: map calls before .Value', IntToStr(Calls), '0');
  Check('From(1).Map(spy).Head', VarText(First.Value), '10');
  VarText(First.Value);
  Check('Head: one element pulled, memoised', IntToStr(Calls), '1');

  try
    TSequence.From(1).Map(Spy).Count;
    Check('Unbounded infinite Count rejected', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('Unbounded infinite Count rejected', 'EFunctional', 'EFunctional');
  end;

  try
    VarText(TSequence.Range(1, 0).Head.Value);
    Check('Head of empty sequence', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('Head of empty sequence', 'EFunctional', 'EFunctional');
  end;
end;

{ TFusion }

procedure TNodeApplication.TestFusion;
var
  Plan: TSequence;
begin
  Section('TFusion - build-time rewrite rules');
  Plan := TSequence.Range(1, 20)
    .Map(TVarFunction.Lift(TFunction.Add(1)))
    .Map(TVarFunction.Lift(TFunction.Multiply(2)))
    .Map(TVarFunction.Lift(TFunction.Add(-3)))
    .Filter(TVarFunction.LiftPredicate(TFunction.GreaterThan(10)))
    .Filter(TVarFunction.LiftPredicate(TFunction.IsOdd()))
    .Take(10)
    .Take(4);
  Check('7 calls fuse into stages', IntToStr(Plan.StageCount), '3');
  Check('  ...plan', Plan.Describe, 'Range(1..20) -> Map{x3} -> Filter{x2} -> Take(4){x2}');
  Check('  ...values', Plan.AsString, '[11, 13, 15, 17]');

  Plan := TSequence.From(1).Drop(5).Drop(5).Take(3);
  Check('Drop(5).Drop(5) plan', Plan.Describe, 'From(1) -> Drop(10){x2} -> Take(3)');
  Check('Drop(0) adds no stage', IntToStr(TSequence.Range(1, 3).Drop(0).StageCount), '0');
end;

{ Entry }

procedure TNodeApplication.DoExecute;
begin
  writeln('qtxFunctional - test suite');
  TestLazyInteger;
  TestLazy;
  TestSequence;
  TestFusion;
  RunRoadmapTests(Check, Section);
  RunExtensionTests(Check, Section);
  RunStage6Tests(Check, Section);
  writeln('');
  writeln(Format('%d passed, %d failed', [FPassed, FFailed]));
end;

end.
