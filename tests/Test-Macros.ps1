#requires -Version 7.2
$ErrorActionPreference='Stop'
if(-not ('VaderMacroStore' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot '..\VaderMacros.cs')}
function Check($condition,$label){if(-not $condition){throw "FAIL: $label"};"PASS: $label"}
function Reject([scriptblock]$action,$label){$rejected=$false;try{& $action}catch{$rejected=$true};Check $rejected $label}
function Same([byte[]]$a,[byte[]]$b){[Convert]::ToHexString($a) -eq [Convert]::ToHexString($b)}
function Tap([byte]$trigger,[string]$name='Tap'){
    $m=[VaderMacro]::new();$m.Trigger=$trigger;$m.Name=$name
    $m.Steps.Add([VaderMacroStep]@{Time=0;Key=4;Event=1});$m.Steps.Add([VaderMacroStep]@{Time=50;Key=4;Event=0});return $m
}
$factory=[byte[]]::new(1660);[Array]::Fill[byte]($factory,255);[Array]::Clear($factory,0,24);$factory[1]=1;[Array]::Clear($factory,1656,4)
$store=[VaderMacroStore]::new($factory)
Check (Same $factory ($store.Encode([VaderMacro[]]@()))) 'Empty store is preserved byte for byte'
$m=Tap 18 '測試';$m.Playback=2;$m.RepeatInterval=100
$encoded=$store.Encode([VaderMacro[]]@($m));$parsed=[VaderMacroStore]::new($encoded)
Check ($encoded[24] -eq 18 -and $encoded[27] -eq 2 -and [BitConverter]::ToUInt16($encoded,28) -eq 100) 'Trigger, playback and repeat interval match the protocol'
Check ($parsed.Macros[0].Name -eq '測試' -and $parsed.Macros[0].Steps[1].Time -eq 50) 'UTF-8 name and cumulative timing round-trip'
Check (Same $encoded ($parsed.Encode([VaderMacro[]]@($parsed.Macros[0].Clone())))) 'Unedited existing macro preserves every byte'
Check (Same $encoded[1656..1659] $factory[1656..1659]) 'Reserved tail is preserved'
$second=Tap 19 'Second';$two=$store.Encode([VaderMacro[]]@($m,$second));$two[30]=0x42
$loaded=[VaderMacroStore]::new($two);$edited=$loaded.Macros[1].Clone();$edited.Name='Changed'
$new=$loaded.Encode([VaderMacro[]]@($loaded.Macros[0].Clone(),$edited))
Check (Same $two[24..63] $new[24..63]) 'Editing another macro preserves the first raw record and reserved header'
$mapping=[byte[]]::new(840);$mapping[0]=2;$mapping[1]=3;$mapping[58]=254;$mapping[67]=15;$mapping[70]=14
$bound=$store.UpdateMapping($mapping,[VaderMacro[]]@($m))
Check ($bound[67] -eq 32 -and $bound[58] -eq 254 -and $bound[70] -eq 14 -and $mapping[67] -eq 15) 'New trigger binding leaves unrelated buttons and input buffer intact'
$removed=$parsed.UpdateMapping($bound,[VaderMacro[]]@())
Check ($removed[67] -eq 255 -and $removed[58] -eq 254) 'Deleting restores only its macro binding to default'
$bound[67]=11;$removed=$parsed.UpdateMapping($bound,[VaderMacro[]]@())
Check ($removed[67] -eq 11) 'Deleting an inactive macro preserves a later normal remap'
Reject {$long=Tap 18 '這個名稱超過二十位元組';[void]$store.Encode([VaderMacro[]]@($long))} 'Long UTF-8 names are rejected without truncation'
Reject {$bad=Tap 18;$bad.Steps.RemoveAt(1);[void]$store.Encode([VaderMacro[]]@($bad))} 'An unreleased key is rejected'
Reject {$bad=Tap 18;$bad.Steps[1].Time=65536;[void]$store.Encode([VaderMacro[]]@($bad))} 'Timestamp overflow is rejected'
Reject {$bad=Tap 18;$bad.Steps[0].Time=60;[void]$store.Encode([VaderMacro[]]@($bad))} 'Time reversal is rejected'
Reject {[void]$store.Encode([VaderMacro[]]@((Tap 18),(Tap 18)))} 'Duplicate trigger keys are rejected'
Reject {$bad=Tap 18;$bad.Steps[0].Key=16;[void]$store.Encode([VaderMacro[]]@($bad))} 'Unsupported macro output is rejected'
Reject {$large=[Collections.Generic.List[VaderMacro]]::new();for($i=0;$i -lt 2;$i++){$item=Tap ([byte](18+$i));for($n=1;$n -lt 128;$n++){$item.Steps.Add([VaderMacroStep]@{Time=2*$n+50;Key=4;Event=1});$item.Steps.Add([VaderMacroStep]@{Time=2*$n+51;Key=4;Event=0})};$large.Add($item)};[void]$store.Encode($large.ToArray())} 'Shared memory capacity is enforced'
Reject {$bad=[byte[]]$two.Clone();$bad[6]=0;$bad[7]=0;[void][VaderMacroStore]::new($bad)} 'Overlapping records are rejected'
'All macro codec checks passed.'
