function Get-VaderMacroState {
    $state=Get-VaderState
    $link=Open-Vader
    try {
        Assert-Firmware $link
        if($link.Request(0xA1)[5] -ne $state.Profile){throw '配置已切換，請重新讀取。'}
        $macros=$link.ReadBlob(0xAC,[byte]$state.Profile)
        $second=$link.ReadBlob(0xAC,[byte]$state.Profile)
        if([Convert]::ToHexString($macros) -ne [Convert]::ToHexString($second)){throw '兩次巨集讀取不同，請重新讀取。'}
        $state | Add-Member -NotePropertyName Macros -NotePropertyValue $macros
        $state | Add-Member -NotePropertyName Store -NotePropertyValue ([VaderMacroStore]::new($macros))
        return $state
    } finally {$link.Dispose()}
}
function Set-VaderMacroState($state,[VaderMacro[]]$macros) {
    $desiredMacros=$state.Store.Encode($macros)
    $desiredMapping=$state.Store.UpdateMapping($state.Mapping,$macros)
    $mapChanged=[Convert]::ToHexString($desiredMapping) -ne [Convert]::ToHexString($state.Mapping)
    $macroChanged=[Convert]::ToHexString($desiredMacros) -ne [Convert]::ToHexString($state.Macros)
    if(-not $mapChanged -and -not $macroChanged){return '設定已相同，沒有重複寫入。'}
    if($mapChanged){
        $oldTag=[BitConverter]::ToUInt16($state.Mapping,225)
        do{$tag=Get-Random -Minimum 0 -Maximum 65535}while($tag -eq $oldTag)
        $desiredMapping[225]=[byte]($tag -band 255);$desiredMapping[226]=[byte]($tag -shr 8)
    }
    $link=Open-Vader;$started=$false;$backup=$null
    try {
        Assert-Firmware $link
        if($link.Request(0xA1)[5] -ne $state.Profile){throw '目前配置已切換，請重新讀取巨集。'}
        $currentMapping=$link.ReadBlob(0xA3,[byte]$state.Profile)
        $currentMacros=$link.ReadBlob(0xAC,[byte]$state.Profile)
        if([Convert]::ToHexString($currentMapping) -ne [Convert]::ToHexString($state.Mapping) -or [Convert]::ToHexString($currentMacros) -ne [Convert]::ToHexString($state.Macros)){throw '映射或巨集已被修改，請重新讀取後再儲存。'}
        $backup=Join-Path $PSScriptRoot ('backups\macros-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        [void](New-Item -ItemType Directory -Path $backup)
        [IO.File]::WriteAllBytes((Join-Path $backup 'mapping-before.bin'),$currentMapping)
        [IO.File]::WriteAllBytes((Join-Path $backup 'macros-before.bin'),$currentMacros)
        [ordered]@{profile=$state.Profile+1;firmware=$state.Firmware;created=(Get-Date -Format o);macroCount=$macros.Count;mappingSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($currentMapping));macrosSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($currentMacros))}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $backup 'backup.json') -Encoding utf8
        $started=$true
        $link.WriteProfileWithMacros([byte]$state.Profile,$desiredMapping,$desiredMacros)
        [IO.File]::WriteAllBytes((Join-Path $backup 'mapping-after.bin'),$desiredMapping)
        [IO.File]::WriteAllBytes((Join-Path $backup 'macros-after.bin'),$desiredMacros)
        return "配置 $($state.Profile+1) 巨集與觸發映射已儲存並完整驗證。備份：$backup"
    } catch {
        $failure=$_.Exception.GetBaseException().Message
        if($started){
            try{$link.WriteProfileWithMacros([byte]$state.Profile,$currentMapping,$currentMacros);$failure+=' 已還原原映射及巨集。'}
            catch{$failure+=" 還原未完成：$($_.Exception.GetBaseException().Message)。備份：$backup"}
        }
        throw $failure
    } finally {$link.Dispose()}
}
