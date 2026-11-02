unit lazyseq.model;

// ---------------------------------------------------------------------------
//  qtxLazySequence - model
//
//  Builds a TSequence pipeline (from the qtxFunctional package) out of a
//  source choice and a list of stage specifications, runs it lazily with
//  instrumentation, and evaluates the same stages eagerly for comparison.
//
//  The lazy run is traced: every function is wrapped so it writes a line
//  as it runs. Reading the trace shows that each element travels through
//  every stage before the next element is even produced.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.sequence;

const
  MaxTraceLines = 400;
  SafetyLimit   = 100000;   // stop runaway pipelines (e.g. a filter nothing passes)

type
  TSourceKind = (skNaturals, skRange20, skRange1000, skPowers, skCollatz);

  TStageKind = (stSquare, stAddOne, stTriple, stEven, stOdd, stPrime,
                stTake, stDrop, stTakeWhile, stScanSum);

  TStageSpec = record
    Kind: TStageKind;
    N:    Integer;
  end;

  TStageSpecs = array of TStageSpec;

  TRunReport = record
    Values:           String;
    Plan:             String;
    WrittenStages:    Integer;
    FusedStages:      Integer;
    SourcePulls:      Integer;
    Calls:            Integer;
    Delivered:        Integer;
    Trace:            String;
    Error:            String;
    EagerPossible:    Boolean;
    EagerValues:      String;
    EagerPulls:       Integer;
    EagerCalls:       Integer;
    EagerArrays:      Integer;
    EagerMaterialised: Integer;
    EagerNote:        String;
  end;

  TRunCounters = class
  public
    Pulls:     Integer;
    Calls:     Integer;
    Delivered: Integer;
  end;

  TTraceBuffer = class
  private
    FText:  String;
    FLines: Integer;
  public
    procedure Add(const Line: String);
    property Text: String read FText;
  end;

  TLazyModel = class
  private
    class function MakeSource(Kind: TSourceKind): TSequence;
    class function RawMap(Kind: TStageKind): TVarFunc;
    class function RawPredicate(const Spec: TStageSpec): TVarPredicate;
    class function WrapMap(const Name: String; const Fn: TVarFunc;
      const C: TRunCounters; const T: TTraceBuffer): TVarFunc;
    class function WrapPredicate(const Name, Yes, No: String; const P: TVarPredicate;
      const C: TRunCounters; const T: TTraceBuffer): TVarPredicate;
    class function WrapFold(const Name: String; const Fn: TVarFoldFunc;
      const C: TRunCounters; const T: TTraceBuffer): TVarFoldFunc;
    class function Tap(const Prefix: String; const T: TTraceBuffer): TVarFunc;
    class function Build(Source: TSourceKind; const Specs: TStageSpecs;
      const C: TRunCounters; const T: TTraceBuffer): TSequence;
    class procedure RunEager(Source: TSourceKind; const Specs: TStageSpecs;
      var Report: TRunReport);
  public
    class function SourceTitle(Kind: TSourceKind): String;
    class function SourceIsInfinite(Kind: TSourceKind): Boolean;
    class function StageTitle(Kind: TStageKind): String;
    class function StageName(const Spec: TStageSpec): String;
    class function NeedsParameter(Kind: TStageKind): Boolean;
    class function Spec(Kind: TStageKind; N: Integer): TStageSpec;
    class function JoinValues(const Items: TVarArray): String;
    class function Run(Source: TSourceKind; const Specs: TStageSpecs): TRunReport;
  end;

implementation

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

function IsPrimeNumber(N: Integer): Boolean;
var
  d: Integer;
begin
  if N < 2 then
    exit(False);
  d := 2;
  while d * d <= N do
  begin
    if (N mod d) = 0 then
      exit(False);
    Inc(d);
  end;
  Result := True;
end;

{ TTraceBuffer }

procedure TTraceBuffer.Add(const Line: String);
begin
  if FLines < MaxTraceLines then
    FText := FText + Line + #10
  else if FLines = MaxTraceLines then
    FText := FText + '... trace stopped after ' + IntToStr(MaxTraceLines) +
      ' lines (the run itself continued)' + #10;
  Inc(FLines);
end;

{ Names }

class function TLazyModel.SourceTitle(Kind: TSourceKind): String;
begin
  case Kind of
    skNaturals:  Result := 'Natural numbers 1, 2, 3, ... (infinite)';
    skRange20:   Result := 'Range 1 .. 20';
    skRange1000: Result := 'Range 1 .. 1000';
    skPowers:    Result := 'Powers of two 1, 2, 4, 8, ... (infinite)';
    skCollatz:   Result := 'Collatz sequence from 27 (infinite)';
  end;
end;

class function TLazyModel.SourceIsInfinite(Kind: TSourceKind): Boolean;
begin
  Result := Kind in [skNaturals, skPowers, skCollatz];
end;

class function TLazyModel.StageTitle(Kind: TStageKind): String;
begin
  case Kind of
    stSquare:    Result := 'Map: square';
    stAddOne:    Result := 'Map: add 1';
    stTriple:    Result := 'Map: times 3';
    stEven:      Result := 'Filter: even';
    stOdd:       Result := 'Filter: odd';
    stPrime:     Result := 'Filter: prime';
    stTake:      Result := 'Take n';
    stDrop:      Result := 'Drop n';
    stTakeWhile: Result := 'TakeWhile: below n';
    stScanSum:   Result := 'Scan: running sum';
  end;
end;

class function TLazyModel.StageName(const Spec: TStageSpec): String;
begin
  case Spec.Kind of
    stSquare:    Result := 'Map square';
    stAddOne:    Result := 'Map +1';
    stTriple:    Result := 'Map x3';
    stEven:      Result := 'Filter even';
    stOdd:       Result := 'Filter odd';
    stPrime:     Result := 'Filter prime';
    stTake:      Result := 'Take ' + IntToStr(Spec.N);
    stDrop:      Result := 'Drop ' + IntToStr(Spec.N);
    stTakeWhile: Result := 'TakeWhile below ' + IntToStr(Spec.N);
    stScanSum:   Result := 'Scan running sum';
  end;
end;

class function TLazyModel.NeedsParameter(Kind: TStageKind): Boolean;
begin
  Result := Kind in [stTake, stDrop, stTakeWhile];
end;

class function TLazyModel.Spec(Kind: TStageKind; N: Integer): TStageSpec;
begin
  Result.Kind := Kind;
  Result.N := N;
end;

class function TLazyModel.JoinValues(const Items: TVarArray): String;
var
  i, Shown: Integer;
begin
  Shown := Length(Items);
  if Shown > 60 then
    Shown := 60;
  Result := '[';
  for i := 0 to Shown - 1 do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + VarText(Items[i]);
  end;
  if Length(Items) > Shown then
    Result := Result + ', ... (' + IntToStr(Length(Items)) + ' values)';
  Result := Result + ']';
end;

{ Raw functions - the actual work, with no instrumentation }

class function TLazyModel.MakeSource(Kind: TSourceKind): TSequence;
begin
  case Kind of
    skNaturals:  Result := TSequence.From(1);
    skRange20:   Result := TSequence.Range(1, 20);
    skRange1000: Result := TSequence.Range(1, 1000);
    skPowers:    Result := TSequence.Iterate(1, TVarFunction.Lift(TFunction.Multiply(2)));
    skCollatz:
      Result := TSequence.Iterate(27,
        function (Value: Variant): Variant
        var
          N: Integer;
        begin
          N := Value;
          if (N mod 2) = 0 then
            Result := N div 2
          else
            Result := 3 * N + 1;
        end);
  end;
end;

class function TLazyModel.RawMap(Kind: TStageKind): TVarFunc;
begin
  case Kind of
    stSquare: Result := TVarFunction.Lift(TFunction.Square());
    stAddOne: Result := TVarFunction.Lift(TFunction.Add(1));
    stTriple: Result := TVarFunction.Lift(TFunction.Multiply(3));
  else
    Result := TVarFunction.Identity();
  end;
end;

class function TLazyModel.RawPredicate(const Spec: TStageSpec): TVarPredicate;
var
  Limit: Integer;
begin
  Limit := Spec.N;
  case Spec.Kind of
    stEven: Result := TVarFunction.LiftPredicate(TFunction.IsEven());
    stOdd:  Result := TVarFunction.LiftPredicate(TFunction.IsOdd());
    stPrime:
      Result := function (Value: Variant): Boolean
        var
          N: Integer;
        begin
          N := Value;
          Result := IsPrimeNumber(N);
        end;
  else
    // stTakeWhile: value below the limit
    Result := function (Value: Variant): Boolean
      var
        N: Integer;
      begin
        N := Value;
        Result := N < Limit;
      end;
  end;
end;

{ Instrumentation wrappers }

class function TLazyModel.WrapMap(const Name: String; const Fn: TVarFunc;
  const C: TRunCounters; const T: TTraceBuffer): TVarFunc;
var
  Title: String;
  F: TVarFunc;
  Counters: TRunCounters;
  Trace: TTraceBuffer;
begin
  Title := Name;
  F := Fn;
  Counters := C;
  Trace := T;
  Result := function (Value: Variant): Variant
    begin
      Result := F(Value);
      Inc(Counters.Calls);
      Trace.Add('    ' + Title + ': ' + VarText(Value) + ' -> ' + VarText(Result));
    end;
end;

class function TLazyModel.WrapPredicate(const Name, Yes, No: String;
  const P: TVarPredicate; const C: TRunCounters; const T: TTraceBuffer): TVarPredicate;
var
  Title, PassWord, FailWord: String;
  Test: TVarPredicate;
  Counters: TRunCounters;
  Trace: TTraceBuffer;
begin
  Title := Name;
  PassWord := Yes;
  FailWord := No;
  Test := P;
  Counters := C;
  Trace := T;
  Result := function (Value: Variant): Boolean
    begin
      Result := Test(Value);
      Inc(Counters.Calls);
      if Result then
        Trace.Add('    ' + Title + ': ' + VarText(Value) + ' ' + PassWord)
      else
        Trace.Add('    ' + Title + ': ' + VarText(Value) + ' ' + FailWord);
    end;
end;

class function TLazyModel.WrapFold(const Name: String; const Fn: TVarFoldFunc;
  const C: TRunCounters; const T: TTraceBuffer): TVarFoldFunc;
var
  Title: String;
  F: TVarFoldFunc;
  Counters: TRunCounters;
  Trace: TTraceBuffer;
begin
  Title := Name;
  F := Fn;
  Counters := C;
  Trace := T;
  Result := function (Accumulator, Value: Variant): Variant
    begin
      Result := F(Accumulator, Value);
      Inc(Counters.Calls);
      Trace.Add('    ' + Title + ': ' + VarText(Accumulator) + ' + ' + VarText(Value) +
        ' -> ' + VarText(Result));
    end;
end;

class function TLazyModel.Tap(const Prefix: String; const T: TTraceBuffer): TVarFunc;
var
  Text: String;
  Trace: TTraceBuffer;
begin
  Text := Prefix;
  Trace := T;
  Result := function (Value: Variant): Variant
    begin
      Trace.Add(Text + VarText(Value));
      Result := Value;
    end;
end;

{ Pipeline construction }

class function TLazyModel.Build(Source: TSourceKind; const Specs: TStageSpecs;
  const C: TRunCounters; const T: TTraceBuffer): TSequence;
var
  Seq: TSequence;
  i: Integer;
  S: TStageSpec;
  Name: String;
  Counters: TRunCounters;
  Trace: TTraceBuffer;
  Instrumented: Boolean;
begin
  Counters := C;
  Trace := T;
  Instrumented := (C <> nil) and (T <> nil);
  Seq := MakeSource(Source);

  if Instrumented then
    Seq := Seq.Map(function (Value: Variant): Variant
      begin
        Inc(Counters.Pulls);
        if Counters.Pulls > SafetyLimit then
          raise EFunctional.Create('Stopped after ' + IntToStr(SafetyLimit) +
            ' source elements - this pipeline may never produce enough values.');
        Trace.Add('pull #' + IntToStr(Counters.Pulls) + ' from source: ' + VarText(Value));
        Result := Value;
      end);

  for i := 0 to High(Specs) do
  begin
    S := Specs[i];
    Name := StageName(S);
    case S.Kind of
      stSquare, stAddOne, stTriple:
        if Instrumented then
          Seq := Seq.Map(WrapMap(Name, RawMap(S.Kind), C, T))
        else
          Seq := Seq.Map(RawMap(S.Kind));

      stEven, stOdd, stPrime:
        if Instrumented then
          Seq := Seq.Filter(WrapPredicate(Name, 'passes', 'is dropped', RawPredicate(S), C, T))
        else
          Seq := Seq.Filter(RawPredicate(S));

      stTakeWhile:
        if Instrumented then
          Seq := Seq.TakeWhile(WrapPredicate(Name, 'continues',
            'fails - the whole pipeline stops', RawPredicate(S), C, T))
        else
          Seq := Seq.TakeWhile(RawPredicate(S));

      stTake:
        begin
          Seq := Seq.Take(S.N);
          if Instrumented then
            Seq := Seq.Map(Tap('    ' + Name + ': passes ', T));
        end;

      stDrop:
        begin
          if Instrumented then
            Seq := Seq.Map(Tap('    ' + Name + ': receives ', T));
          Seq := Seq.Drop(S.N);
          if Instrumented then
            Seq := Seq.Map(Tap('    ' + Name + ': passes ', T));
        end;

      stScanSum:
        if Instrumented then
          Seq := Seq.Scan(0, WrapFold(Name, TVarFunction.LiftFold(TFunction.Sum()), C, T))
        else
          Seq := Seq.Scan(0, TVarFunction.LiftFold(TFunction.Sum()));
    end;
  end;

  if Instrumented then
    Seq := Seq.Map(function (Value: Variant): Variant
      begin
        Inc(Counters.Delivered);
        Trace.Add('    => result #' + IntToStr(Counters.Delivered) + ' = ' + VarText(Value));
        Result := Value;
      end);

  Result := Seq;
end;

{ Eager evaluation of the same stages }

class procedure TLazyModel.RunEager(Source: TSourceKind; const Specs: TStageSpecs;
  var Report: TRunReport);
var
  Data, Next: TVarArray;
  i, k: Integer;
  S: TStageSpec;
  F: TVarFunc;
  P: TVarPredicate;
  Acc: Variant;
  Stopped: Boolean;
begin
  if SourceIsInfinite(Source) then
  begin
    Report.EagerPossible := False;
    Report.EagerNote := 'The source is infinite. Eager evaluation builds the complete list ' +
      'before the first stage can run, so it would never finish. Lazy evaluation only ' +
      'produces as many elements as the later stages ask for.';
    exit;
  end;

  Report.EagerPossible := True;
  Data := MakeSource(Source).ToArray;
  Report.EagerPulls := Length(Data);
  Report.EagerArrays := 1;
  Report.EagerMaterialised := Length(Data);
  Report.EagerCalls := 0;

  for i := 0 to High(Specs) do
  begin
    S := Specs[i];
    Next := [];
    case S.Kind of
      stSquare, stAddOne, stTriple:
        begin
          F := RawMap(S.Kind);
          for k := 0 to High(Data) do
            Next.Add(F(Data[k]));
          Report.EagerCalls := Report.EagerCalls + Length(Data);
        end;
      stEven, stOdd, stPrime:
        begin
          P := RawPredicate(S);
          for k := 0 to High(Data) do
            if P(Data[k]) then
              Next.Add(Data[k]);
          Report.EagerCalls := Report.EagerCalls + Length(Data);
        end;
      stTakeWhile:
        begin
          P := RawPredicate(S);
          Stopped := False;
          for k := 0 to High(Data) do
            if not Stopped then
            begin
              Report.EagerCalls := Report.EagerCalls + 1;
              if P(Data[k]) then
                Next.Add(Data[k])
              else
                Stopped := True;
            end;
        end;
      stTake:
        for k := 0 to High(Data) do
          if k < S.N then
            Next.Add(Data[k]);
      stDrop:
        for k := 0 to High(Data) do
          if k >= S.N then
            Next.Add(Data[k]);
      stScanSum:
        begin
          Acc := 0;
          for k := 0 to High(Data) do
          begin
            Acc := TVarFunction.LiftFold(TFunction.Sum())(Acc, Data[k]);
            Next.Add(Acc);
          end;
          Report.EagerCalls := Report.EagerCalls + Length(Data);
        end;
    end;
    Data := Next;
    Inc(Report.EagerArrays);
    Report.EagerMaterialised := Report.EagerMaterialised + Length(Data);
  end;

  Report.EagerValues := JoinValues(Data);
end;

{ Run }

class function TLazyModel.Run(Source: TSourceKind; const Specs: TStageSpecs): TRunReport;
var
  Plain, Traced: TSequence;
  C: TRunCounters;
  T: TTraceBuffer;
begin
  // The plain pipeline shows the plan exactly as the library fuses it
  Plain := Build(Source, Specs, nil, nil);
  Result.Plan := Plain.Describe;
  Result.FusedStages := Plain.StageCount;
  Result.WrittenStages := Length(Specs);

  C := TRunCounters.Create;
  T := TTraceBuffer.Create;
  try
    Traced := Build(Source, Specs, C, T);
    Result.Values := JoinValues(Traced.ToArray);
  except
    on E: Exception do
      Result.Error := E.Message;
  end;
  Result.SourcePulls := C.Pulls;
  Result.Calls := C.Calls;
  Result.Delivered := C.Delivered;
  Result.Trace := T.Text;

  RunEager(Source, Specs, Result);
end;

end.
