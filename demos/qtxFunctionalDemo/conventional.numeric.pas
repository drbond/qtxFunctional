unit conventional.numeric;

// ---------------------------------------------------------------------------
//  Conventional (imperative) Pascal baselines for Stage 6 benchmarks.
//
//  Written the way these algorithms are usually written in Pascal: plain
//  loops, mutable arrays updated in place, no closures, no immutability.
//  Each routine mirrors a functional counterpart so results can be compared
//  and timed side by side.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.floats;

type
  TCellArray = array of Integer;

  TConventional = class
  public
    // Vectors and matrices (flat row-major arrays)
    class function Dot(const A, B: TFloatArray): Float;
    class function MatMul(const A, B: TFloatArray; N: Integer): TFloatArray;

    // In-place iterative radix-2 FFT (Re/Im arrays are overwritten)
    class procedure FFTInPlace(var Re, Im: TFloatArray);

    // Elementary automaton with two swapped buffers; returns final generation
    class function RunAutomaton(RuleNumber, Width, Steps: Integer): String;

    // XOR network trained with mutable weight and gradient arrays
    class function TrainXor(Hidden, Seed: Integer; Rate: Float; Epochs: Integer): TFloatArray;
    class function PredictXor(const P: TFloatArray; Hidden: Integer; X1, X2: Float): Float;
  end;

implementation

function Sig(Z: Float): Float;
begin
  Result := 1 / (1 + Exp(-Z));
end;

class function TConventional.Dot(const A, B: TFloatArray): Float;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(A) do
    Result := Result + A[i] * B[i];
end;

class function TConventional.MatMul(const A, B: TFloatArray; N: Integer): TFloatArray;
var
  i, j, k: Integer;
  Sum: Float;
begin
  for i := 0 to N * N - 1 do
    Result.Add(0);
  for i := 0 to N - 1 do
    for j := 0 to N - 1 do
    begin
      Sum := 0;
      for k := 0 to N - 1 do
        Sum := Sum + A[i * N + k] * B[k * N + j];
      Result[i * N + j] := Sum;
    end;
end;

class procedure TConventional.FFTInPlace(var Re, Im: TFloatArray);
var
  N, i, j, Bit, Len, Half, Start, K: Integer;
  T, Angle, WRe, WIm, URe, UIm, VRe, VIm: Float;
begin
  N := Length(Re);

  // Bit-reversal permutation
  j := 0;
  for i := 1 to N - 1 do
  begin
    Bit := N shr 1;
    while (j and Bit) <> 0 do
    begin
      j := j xor Bit;
      Bit := Bit shr 1;
    end;
    j := j xor Bit;
    if i < j then
    begin
      T := Re[i]; Re[i] := Re[j]; Re[j] := T;
      T := Im[i]; Im[i] := Im[j]; Im[j] := T;
    end;
  end;

  // Butterflies
  Len := 2;
  while Len <= N do
  begin
    Half := Len div 2;
    Start := 0;
    while Start < N do
    begin
      for K := 0 to Half - 1 do
      begin
        Angle := -2 * Pi * K / Len;
        WRe := Cos(Angle);
        WIm := Sin(Angle);
        URe := Re[Start + K];
        UIm := Im[Start + K];
        VRe := Re[Start + K + Half] * WRe - Im[Start + K + Half] * WIm;
        VIm := Re[Start + K + Half] * WIm + Im[Start + K + Half] * WRe;
        Re[Start + K] := URe + VRe;
        Im[Start + K] := UIm + VIm;
        Re[Start + K + Half] := URe - VRe;
        Im[Start + K + Half] := UIm - VIm;
      end;
      Start := Start + Len;
    end;
    Len := Len * 2;
  end;
end;

class function TConventional.RunAutomaton(RuleNumber, Width, Steps: Integer): String;
var
  Cur, Nxt, Tmp: TCellArray;
  i, s, Pattern: Integer;
begin
  for i := 0 to Width - 1 do
  begin
    Cur.Add(0);
    Nxt.Add(0);
  end;
  Cur[Width div 2] := 1;

  for s := 1 to Steps do
  begin
    for i := 0 to Width - 1 do
    begin
      Pattern := Cur[(i - 1 + Width) mod Width] * 4 + Cur[i] * 2 + Cur[(i + 1) mod Width];
      Nxt[i] := (RuleNumber shr Pattern) and 1;
    end;
    Tmp := Cur;
    Cur := Nxt;
    Nxt := Tmp;
  end;

  Result := '';
  for i := 0 to Width - 1 do
    if Cur[i] = 1 then
      Result := Result + '1'
    else
      Result := Result + '0';
end;

class function TConventional.PredictXor(const P: TFloatArray; Hidden: Integer;
  X1, X2: Float): Float;
var
  j, H: Integer;
  Z, Hj: Float;
begin
  H := Hidden;
  Z := 0;
  for j := 0 to H - 1 do
  begin
    Hj := Sig(P[2 * j] * X1 + P[2 * j + 1] * X2 + P[2 * H + j]);
    Z := Z + P[3 * H + j] * Hj;
  end;
  Result := Sig(Z + P[4 * H]);
end;

class function TConventional.TrainXor(Hidden, Seed: Integer; Rate: Float;
  Epochs: Integer): TFloatArray;
var
  P, G, Act, X1s, X2s, Ys: TFloatArray;
  H, Count, e, s, j, i: Integer;
  S0, Z, O, DeltaO, DeltaH: Float;
begin
  H := Hidden;
  Count := 4 * H + 1;

  // Same Park-Miller initialisation as TNetwork.InitialWeights
  S0 := Seed;
  for i := 1 to Count do
  begin
    S0 := S0 * 16807;
    S0 := S0 - Trunc(S0 / 2147483647) * 2147483647;
    P.Add((S0 / 2147483647) * 2 - 1);
    G.Add(0);
  end;
  for j := 0 to H - 1 do
    Act.Add(0);

  X1s := [0.0, 0.0, 1.0, 1.0];
  X2s := [0.0, 1.0, 0.0, 1.0];
  Ys  := [0.0, 1.0, 1.0, 0.0];

  for e := 1 to Epochs do
  begin
    for i := 0 to Count - 1 do
      G[i] := 0;

    for s := 0 to 3 do
    begin
      Z := 0;
      for j := 0 to H - 1 do
      begin
        Act[j] := Sig(P[2 * j] * X1s[s] + P[2 * j + 1] * X2s[s] + P[2 * H + j]);
        Z := Z + P[3 * H + j] * Act[j];
      end;
      O := Sig(Z + P[4 * H]);
      DeltaO := (O - Ys[s]) * O * (1 - O);
      for j := 0 to H - 1 do
      begin
        G[3 * H + j] := G[3 * H + j] + DeltaO * Act[j];
        DeltaH := DeltaO * P[3 * H + j] * Act[j] * (1 - Act[j]);
        G[2 * j] := G[2 * j] + DeltaH * X1s[s];
        G[2 * j + 1] := G[2 * j + 1] + DeltaH * X2s[s];
        G[2 * H + j] := G[2 * H + j] + DeltaH;
      end;
      G[4 * H] := G[4 * H] + DeltaO;
    end;

    for i := 0 to Count - 1 do
      P[i] := P[i] - Rate * (G[i] / 4);
  end;

  Result := P;
end;

end.
