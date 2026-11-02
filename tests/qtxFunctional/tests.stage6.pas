unit tests.stage6;

// ---------------------------------------------------------------------------
//  qtxFunctional - Stage 6 tests and benchmarks
//
//  Expected values were computed independently (Python reference
//  implementations) before this code was written.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.floats,
  functional.stats,
  functional.sequence,
  functional.vector,
  functional.fft,
  functional.automata,
  functional.neural,
  conventional.numeric,
  tests.roadmap;

procedure RunStage6Tests(const Check: TCheckProc; const Section: TSectionProc);

implementation

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

function Ms(Started: Float): Float;
begin
  Result := (Now - Started) * 86400000;
end;

function PadRight(const S: String; Width: Integer): String;
begin
  Result := S;
  while Length(Result) < Width do
    Result := Result + ' ';
end;

function PadLeft(const S: String; Width: Integer): String;
begin
  Result := S;
  while Length(Result) < Width do
    Result := ' ' + Result;
end;

procedure BenchRow(const Name: String; FunctionalMs, ConventionalMs: Float; const Agree: String);
var
  Ratio: String;
begin
  if ConventionalMs > 0 then
    Ratio := FormatNum(FunctionalMs / ConventionalMs, 1) + 'x'
  else
    Ratio := 'n/a';
  writeln('  ' + PadRight(Name, 34) +
    PadLeft(FormatNum(FunctionalMs, 0) + ' ms', 10) +
    PadLeft(FormatNum(ConventionalMs, 0) + ' ms', 14) +
    PadLeft(Ratio, 9) + '   ' + Agree);
end;

function TestSignal(Size: Integer): TFloatArray;
var
  i: Integer;
begin
  for i := 0 to Size - 1 do
    Result.Add(Sin(i * 0.37) + 0.5 * Cos(i * 1.91));
end;

function MaxAbsDiff(const A, B: TFloatArray): Float;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do
    if Abs(A[i] - B[i]) > Result then
      Result := Abs(A[i] - B[i]);
end;

{ Vectors and matrices }

procedure TestVectors(const Check: TCheckProc; const Section: TSectionProc);
var
  A, B: TVector;
  M, Rot: TMatrix;
  Product: TMatrix;
  FusedArrays, UnfusedArrays: Integer;
  V: TFloatArray;
begin
  Section('Stage 6 - vectors and matrices');
  A := TVector.Tabulate(3, function (Index: Integer): Float begin Result := Index + 1; end);
  B := TVector.Tabulate(3, function (Index: Integer): Float begin Result := Index + 4; end);
  Check('A + B', A.Add(B).AsString, '[5, 7, 9]');
  Check('A.Scale(2)', A.Scale(2).AsString, '[2, 4, 6]');
  Check('A . B', FormatNum(A.Dot(B), 6), '32');

  TFunctionalStats.Reset;
  A.Dot(B);
  FusedArrays := TFunctionalStats.IntermediateArrays;
  TFunctionalStats.Reset;
  A.DotUnfused(B);
  UnfusedArrays := TFunctionalStats.IntermediateArrays;
  Check('Arrays allocated: fused Dot / ZipWith+Fold',
    IntToStr(FusedArrays) + ' / ' + IntToStr(UnfusedArrays), '0 / 1');

  V := [3.0, 4.0];
  Check('Norm of [3, 4]', FormatNum(TVector.Create(V).Norm, 6), '5');

  M := TMatrix.Tabulate(2, 3,
    function (Row, Col: Integer): Float begin Result := Row * 3 + Col + 1; end);
  Check('M transposed, row 0', M.Transpose.Row(0).AsString, '[1, 4]');
  Product := M.Multiply(M.Transpose);
  Check('M x Mt, row 0', Product.Row(0).AsString, '[14, 32]');
  Check('M x Mt, row 1', Product.Row(1).AsString, '[32, 77]');
  Check('I x M = M', TMatrix.Identity(2).Multiply(M).Row(1).AsString, '[4, 5, 6]');

  Rot := TMatrix.Tabulate(2, 2,
    function (Row, Col: Integer): Float
    begin
      // 90 degree rotation [[0, -1], [1, 0]]
      if (Row = 0) and (Col = 1) then Result := -1
      else if (Row = 1) and (Col = 0) then Result := 1
      else Result := 0;
    end);
  V := [1.0, 0.0];
  Check('Rotate [1, 0] by 90 degrees', Rot.Apply(TVector.Create(V)).AsString, '[0, 1]');
end;

{ Fourier }

procedure TestFourier(const Check: TCheckProc; const Section: TSectionProc);
var
  Box, Wave, Sig, Re, Im: TFloatArray;
  Spectrum, X, F, D: TComplexArray;
  i, Peak: Integer;
  Mags: TFloatArray;
begin
  Section('Stage 6 - Fourier transforms');
  Box := [1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0];
  Spectrum := TFourier.FFT(TFourier.FromReals(Box));
  Check('|FFT| of [1,1,1,1,0,0,0,0]',
    TVector.Create(TFourier.Magnitudes(Spectrum)).AsString(3),
    '[4, 2.613, 0, 1.082, 0, 1.082, 0, 2.613]');

  for i := 0 to 63 do
    Wave.Add(Sin(2 * Pi * 3 * i / 64));
  Mags := TFourier.Magnitudes(TFourier.FFT(TFourier.FromReals(Wave)));
  Peak := 0;
  for i := 1 to 31 do
    if Mags[i] > Mags[Peak] then
      Peak := i;
  Check('3-cycle sine: peak frequency bin', IntToStr(Peak), '3');
  Check('3-cycle sine: peak magnitude (n/2)', FormatNum(Mags[3], 6), '32');

  X := TFourier.FromReals(TestSignal(64));
  F := TFourier.FFT(X);
  D := TFourier.DFT(X);
  Check('FFT agrees with direct DFT (n=64)',
    BoolToStr(TFourier.MaxDifference(F, D) < 1e-9), BoolToStr(True));
  Check('InverseFFT(FFT(x)) = x',
    BoolToStr(TFourier.MaxDifference(TFourier.InverseFFT(F), X) < 1e-12), BoolToStr(True));

  Sig := TestSignal(256);
  F := TFourier.FFT(TFourier.FromReals(Sig));
  Re := Sig;
  for i := 0 to 255 do
    Im.Add(0);
  TConventional.FFTInPlace(Re, Im);
  Check('Functional FFT = conventional in-place FFT (n=256)',
    BoolToStr((MaxAbsDiff(TFourier.RealParts(F), Re) < 1e-9)), BoolToStr(True));

  try
    TFourier.FFT(TFourier.FromReals([1.0, 2.0, 3.0]));
    Check('Non-power-of-two length rejected', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('Non-power-of-two length rejected', 'EFunctional', 'EFunctional');
  end;
end;

{ Cellular automata }

procedure TestAutomata(const Check: TCheckProc; const Section: TSectionProc);
var
  Rows: TVarArray;
  i: Integer;
  Functional, Conventional: String;
begin
  Section('Stage 6 - cellular automata');
  Check('Rule 90 populations, generations 0-7',
    TAutomaton.Generations(90, TAutomaton.SingleCell(63))
      .Map(TAutomaton.PopulationOf).Take(8).AsString,
    '[1, 2, 2, 4, 2, 4, 4, 8]');
  Check('Rule 30 centre column (pseudo-random)',
    TAutomaton.Generations(30, TAutomaton.SingleCell(101))
      .Map(TAutomaton.CentreCell).Take(16).AsString,
    '[1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 1]');

  Functional := TAutomaton.Generations(110, TAutomaton.SingleCell(201)).Drop(150).Head.Value;
  Conventional := TConventional.RunAutomaton(110, 201, 150);
  Check('Rule 110 gen 150: functional = conventional',
    BoolToStr(Functional = Conventional), BoolToStr(True));

  writeln('  info  Rule 90 from a single cell (Sierpinski triangle):');
  Rows := TAutomaton.Generations(90, TAutomaton.SingleCell(33))
    .Map(TAutomaton.RenderOf).Take(16).ToArray;
  for i := 0 to High(Rows) do
    writeln('          ' + VarText(Rows[i]));
end;

{ Neural network }

procedure TestNeural(const Check: TCheckProc; const Section: TSectionProc);
var
  Samples: TSampleArray;
  Untrained, Trained: TNetwork;
  Outputs: String;
  i: Integer;
  AllCorrect: Boolean;
  P: TFloatArray;
  Predicted: Float;
begin
  Section('Stage 6 - neural network (2-4-1 MLP learning XOR)');
  Samples := TNetwork.XorSamples;
  Untrained := TNetwork.Initial(4, 42);
  Trained := Untrained.Train(Samples, 2.0, 3000);

  Outputs := '';
  AllCorrect := True;
  for i := 0 to High(Samples) do
  begin
    Predicted := Trained.Predict(Samples[i].X1, Samples[i].X2);
    if i > 0 then
      Outputs := Outputs + ', ';
    Outputs := Outputs + FormatNum(Predicted, 3);
    if Round(Predicted) <> Round(Samples[i].Y) then
      AllCorrect := False;
  end;
  Check('Outputs for 00, 01, 10, 11 after 3000 epochs', Outputs, '0.02, 0.97, 0.966, 0.043');
  Check('Every XOR case classified correctly', BoolToStr(AllCorrect), BoolToStr(True));
  Check('Training loss (MSE)', FormatNum(Trained.Loss(Samples), 6), '0.001071');
  Check('Original untrained network unchanged',
    BoolToStr(Untrained.Loss(Samples) > 0.2), BoolToStr(True));

  P := TConventional.TrainXor(4, 42, 2.0, 3000);
  Check('Weights identical to conventional training',
    BoolToStr(MaxAbsDiff(Trained.Params.ToArray, P) < 1e-12), BoolToStr(True));
end;

{ Benchmarks }

procedure RunBenchmarks;
var
  Started, F, C: Float;
  A, B: TVector;
  AA, BB, Flat1, Flat2, Re, Im, Sig: TFloatArray;
  M1, M2: TMatrix;
  FunctionalProduct: TMatrix;
  ConventionalProduct: TFloatArray;
  Spectrum: TComplexArray;
  Gen1, Gen2: String;
  Net: TNetwork;
  P: TFloatArray;
  Sum1, Sum2: Float;
  i, r: Integer;
  Agree: String;
  N: Integer;
begin
  writeln('');
  writeln('Stage 6 - performance: functional vs conventional Pascal (Node.js)');
  writeln('  ' + PadRight('Workload', 34) + PadLeft('Functional', 10) +
    PadLeft('Conventional', 14) + PadLeft('Ratio', 9) + '   Results');

  // 1. Dot product
  A := TVector.Tabulate(1000000, function (Index: Integer): Float begin Result := Sin(Index); end);
  B := TVector.Tabulate(1000000, function (Index: Integer): Float begin Result := Cos(Index); end);
  AA := A.ToArray;
  BB := B.ToArray;
  Started := Now;
  Sum1 := 0;
  for r := 1 to 5 do
    Sum1 := Sum1 + A.Dot(B);
  F := Ms(Started);
  Started := Now;
  Sum2 := 0;
  for r := 1 to 5 do
    Sum2 := Sum2 + TConventional.Dot(AA, BB);
  C := Ms(Started);
  if Abs(Sum1 - Sum2) < 1e-6 then Agree := 'agree' else Agree := 'DIFFER';
  BenchRow('Dot product, 1M elements x5', F, C, Agree);

  // 2. Matrix multiply
  N := 100;
  M1 := TMatrix.Tabulate(N, N, function (Row, Col: Integer): Float begin Result := Sin(Row + 2 * Col); end);
  M2 := TMatrix.Tabulate(N, N, function (Row, Col: Integer): Float begin Result := Cos(Row - Col); end);
  for i := 0 to N * N - 1 do
  begin
    Flat1.Add(M1.Get(i div N, i mod N));
    Flat2.Add(M2.Get(i div N, i mod N));
  end;
  Started := Now;
  FunctionalProduct := M1.Multiply(M2);
  F := Ms(Started);
  Started := Now;
  ConventionalProduct := TConventional.MatMul(Flat1, Flat2, N);
  C := Ms(Started);
  Agree := 'agree';
  for i := 0 to N * N - 1 do
    if Abs(FunctionalProduct.Get(i div N, i mod N) - ConventionalProduct[i]) > 1e-9 then
      Agree := 'DIFFER';
  BenchRow('Matrix multiply, 100 x 100', F, C, Agree);

  // 3. FFT
  Sig := TestSignal(4096);
  Started := Now;
  for r := 1 to 5 do
    Spectrum := TFourier.FFT(TFourier.FromReals(Sig));
  F := Ms(Started);
  Started := Now;
  for r := 1 to 5 do
  begin
    Re := [];
    Im := [];
    for i := 0 to High(Sig) do
    begin
      Re.Add(Sig[i]);
      Im.Add(0);
    end;
    TConventional.FFTInPlace(Re, Im);
  end;
  C := Ms(Started);
  if MaxAbsDiff(TFourier.RealParts(Spectrum), Re) < 1e-8 then Agree := 'agree' else Agree := 'DIFFER';
  BenchRow('FFT, 4096 points x5', F, C, Agree);

  // 4. Cellular automaton
  Started := Now;
  Gen1 := TAutomaton.Generations(110, TAutomaton.SingleCell(401)).Drop(400).Head.Value;
  F := Ms(Started);
  Started := Now;
  Gen2 := TConventional.RunAutomaton(110, 401, 400);
  C := Ms(Started);
  if Gen1 = Gen2 then Agree := 'agree' else Agree := 'DIFFER';
  BenchRow('Rule 110, 401 cells x 400 gens', F, C, Agree);

  // 5. Neural network training
  Started := Now;
  Net := TNetwork.Initial(4, 42).Train(TNetwork.XorSamples, 2.0, 3000);
  F := Ms(Started);
  Started := Now;
  P := TConventional.TrainXor(4, 42, 2.0, 3000);
  C := Ms(Started);
  if MaxAbsDiff(Net.Params.ToArray, P) < 1e-12 then Agree := 'agree' else Agree := 'DIFFER';
  BenchRow('XOR MLP 2-4-1, 3000 epochs', F, C, Agree);
end;

procedure RunStage6Tests(const Check: TCheckProc; const Section: TSectionProc);
begin
  TestVectors(Check, Section);
  TestFourier(Check, Section);
  TestAutomata(Check, Section);
  TestNeural(Check, Section);
  RunBenchmarks;
end;

end.
