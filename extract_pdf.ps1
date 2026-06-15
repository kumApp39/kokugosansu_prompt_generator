$ErrorActionPreference='Stop'
$base="C:\Users\jyuso\Desktop\project_ClaudeCode\アプリ開発\国語算数プロンプトジェネレータ"
$pdf=Join-Path $base "ラーニングマップ\ラーニングマップ.pdf"
$b=[System.IO.File]::ReadAllBytes($pdf)
$enc=[System.Text.Encoding]::GetEncoding(28591)
$all=$enc.GetString($b)
function Inflate($bytes){
  try{
    $ms=New-Object System.IO.MemoryStream(,$bytes); $ms.ReadByte()|Out-Null; $ms.ReadByte()|Out-Null
    $ds=New-Object System.IO.Compression.DeflateStream($ms,[System.IO.Compression.CompressionMode]::Decompress)
    $out=New-Object System.IO.MemoryStream; $ds.CopyTo($out); $ds.Close(); return $out.ToArray()
  }catch{ return $null }
}
# collect streams
$streams=New-Object System.Collections.ArrayList
$pos=0
while($true){
  $s=$all.IndexOf("stream",$pos); if($s -lt 0){break}
  $k=$s+6; if($b[$k] -eq 0x0D){$k++}; if($b[$k] -eq 0x0A){$k++}
  $e=$all.IndexOf("endstream",$k); if($e -lt 0){break}
  $len=$e-$k
  if($len -gt 0){ $raw=New-Object byte[] $len; [Array]::Copy($b,$k,$raw,0,$len); [void]$streams.Add($raw) }
  $pos=$e+9
}
# build CMap
$cmap=@{}
foreach($st in $streams){
  $inf=Inflate $st; if($inf -eq $null){continue}
  $t=$enc.GetString($inf)
  if(-not ($t.Contains("beginbfchar") -or $t.Contains("beginbfrange"))){continue}
  foreach($m in [regex]::Matches($t,'beginbfchar(.*?)endbfchar',[System.Text.RegularExpressions.RegexOptions]::Singleline)){
    foreach($e2 in [regex]::Matches($m.Groups[1].Value,'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')){
      $src=[Convert]::ToInt32($e2.Groups[1].Value,16); $dstHex=$e2.Groups[2].Value; $ch=""
      for($z=0;$z -lt $dstHex.Length;$z+=4){ $ch+=[char][Convert]::ToInt32($dstHex.Substring($z,4),16) }
      $cmap[$src]=$ch
    }
  }
  foreach($m in [regex]::Matches($t,'beginbfrange(.*?)endbfrange',[System.Text.RegularExpressions.RegexOptions]::Singleline)){
    foreach($e2 in [regex]::Matches($m.Groups[1].Value,'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')){
      $lo=[Convert]::ToInt32($e2.Groups[1].Value,16); $hi=[Convert]::ToInt32($e2.Groups[2].Value,16); $bs=[Convert]::ToInt32($e2.Groups[3].Value,16)
      for($c=$lo;$c -le $hi;$c++){ $cmap[$c]=[char]($bs+($c-$lo)) }
    }
  }
}
function DecodeHex($hex){
  $s=New-Object System.Text.StringBuilder
  for($z=0;$z+4 -le $hex.Length;$z+=4){
    $code=[Convert]::ToInt32($hex.Substring($z,4),16)
    if($cmap.ContainsKey($code)){ [void]$s.Append($cmap[$code]) }
  }
  return $s.ToString()
}
# decode each text content stream into positioned fragments
$pages=New-Object System.Collections.ArrayList
foreach($st in $streams){
  $inf=Inflate $st; if($inf -eq $null){continue}
  $t=$enc.GetString($inf)
  if(-not ($t.Contains("BT") -and ($t.Contains(" Tj") -or $t.Contains(" TJ")))){continue}
  $frags=New-Object System.Collections.ArrayList
  $curX=0.0;$curY=0.0
  # tokenize by lines/operators using regex over the stream
  foreach($line in ($t -split "`n")){
    # Tm: a b c d e f Tm
    $mtm=[regex]::Match($line,'([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+Tm')
    if($mtm.Success){ $curX=[double]$mtm.Groups[5].Value; $curY=[double]$mtm.Groups[6].Value }
    $mtd=[regex]::Match($line,'([-0-9.]+)\s+([-0-9.]+)\s+T[dD]')
    if($mtd.Success){ $curX+=[double]$mtd.Groups[1].Value; $curY+=[double]$mtd.Groups[2].Value }
    # show text: collect all <hex> in this line (Tj or TJ array)
    $hexes=[regex]::Matches($line,'<([0-9A-Fa-f]+)>')
    if($hexes.Count -gt 0){
      $txt=""
      foreach($h in $hexes){ $txt+=DecodeHex $h.Groups[1].Value }
      if($txt.Trim().Length -gt 0){
        [void]$frags.Add([pscustomobject]@{x=[math]::Round($curX); y=[math]::Round($curY); text=$txt})
      }
    }
  }
  if($frags.Count -gt 0){
    $title=($frags | Select-Object -First 6 | ForEach-Object {$_.text}) -join ""
    [void]$pages.Add([pscustomobject]@{title=$title; frags=$frags})
  }
}
"テキストページ数: $($pages.Count)"
# 出力: 各ページのタイトルと座標付きフラグメント
$outFile=Join-Path $base "ラーニングマップ\_pdf_extract\pdf_text.txt"
$w=New-Object System.Text.StringBuilder
$pn=0
foreach($p in $pages){
  $pn++
  [void]$w.AppendLine("==================== PAGE $pn ====================")
  [void]$w.AppendLine("TITLE: $($p.title)")
  # sort by y desc (top first), then x asc
  foreach($f in ($p.frags | Sort-Object @{e={$_.y};Descending=$true}, @{e={$_.x}})){
    [void]$w.AppendLine(("[x={0,5} y={1,5}] {2}" -f $f.x,$f.y,$f.text))
  }
}
[System.IO.File]::WriteAllText($outFile,$w.ToString(),(New-Object System.Text.UTF8Encoding($false)))
"WROTE $outFile ($((Get-Item $outFile).Length) bytes)"
# タイトル一覧
$pn=0; foreach($p in $pages){ $pn++; "P$pn : $($p.title)" }