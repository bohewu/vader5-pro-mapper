$macroPage=[Windows.Forms.TabPage]::new('巨集');[void]$tabs.TabPages.Add($macroPage)
$macroLayout=[Windows.Forms.TableLayoutPanel]::new();$macroLayout.Dock='Fill';$macroLayout.Padding=[Windows.Forms.Padding]::new(12);$macroLayout.ColumnCount=1;$macroLayout.RowCount=7
[void]$macroLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
foreach($kind in @('AutoSize','AutoSize','AutoSize','AutoSize','Percent','AutoSize','AutoSize')){[void]$macroLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::$kind,100))};$macroPage.Controls.Add($macroLayout)
$macroHint=[Windows.Forms.Label]::new();$macroHint.AutoSize=$true;$macroHint.Dock='Fill';$macroHint.Text="建立板載按鍵序列；儲存後不用常駐工具。`n儲存會將觸發鍵改為播放巨集。刪除後，其巨集映射恢復預設。";$macroLayout.Controls.Add($macroHint,0,0)
$macroToolbar=[Windows.Forms.FlowLayoutPanel]::new();$macroToolbar.AutoSize=$true;$macroToolbar.Dock='Fill';$macroLayout.Controls.Add($macroToolbar,0,1)
foreach($spec in @(@('macroReload','重新讀取'),@('macroNew','新增巨集'),@('macroDelete','刪除巨集'),@('macroSave','儲存巨集到手把'))){$b=[Windows.Forms.Button]::new();$b.Text=$spec[1];$b.AutoSize=$true;$b.MinimumSize=[Drawing.Size]::new(105,36);Set-Variable -Name $spec[0] -Value $b;$macroToolbar.Controls.Add($b)}
$macroSelect=[Windows.Forms.ComboBox]::new();$macroSelect.DropDownStyle='DropDownList';$macroSelect.Dock='Fill';$macroLayout.Controls.Add($macroSelect,0,2)
$macroFields=[Windows.Forms.FlowLayoutPanel]::new();$macroFields.AutoSize=$true;$macroFields.Dock='Fill';$macroLayout.Controls.Add($macroFields,0,3)
foreach($text in @('觸發鍵','名稱','播放模式','重複間隔 ms')){
    $label=[Windows.Forms.Label]::new();$label.Text=$text;$label.AutoSize=$true;$label.Margin=[Windows.Forms.Padding]::new(3,8,3,3);$macroFields.Controls.Add($label)
    switch($text){
        '觸發鍵'{$macroTrigger=[Windows.Forms.ComboBox]::new();$macroTrigger.DropDownStyle='DropDownList';$macroTrigger.Width=72;foreach($key in $script:KeyIds.Keys){[void]$macroTrigger.Items.Add($key)};$macroFields.Controls.Add($macroTrigger)}
        '名稱'{$macroName=[Windows.Forms.TextBox]::new();$macroName.Width=130;$macroFields.Controls.Add($macroName)}
        '播放模式'{$macroPlayback=[Windows.Forms.ComboBox]::new();$macroPlayback.DropDownStyle='DropDownList';$macroPlayback.Width=120;[void]$macroPlayback.Items.AddRange([object[]]@('單次','按住重複','切換重複'));$macroFields.Controls.Add($macroPlayback)}
        '重複間隔 ms'{$macroRepeat=[Windows.Forms.NumericUpDown]::new();$macroRepeat.Maximum=65534;$macroRepeat.Width=85;$macroFields.Controls.Add($macroRepeat)}
    }
}
$macroSteps=[Windows.Forms.DataGridView]::new();$macroSteps.Dock='Fill';$macroSteps.AllowUserToAddRows=$false;$macroSteps.AllowUserToDeleteRows=$false;$macroSteps.RowHeadersVisible=$false;$macroSteps.AutoSizeColumnsMode='Fill';$macroSteps.SelectionMode='FullRowSelect';$macroSteps.MultiSelect=$false;$macroSteps.BackgroundColor=[Drawing.Color]::White;$macroSteps.RowTemplate.Height=28;$macroSteps.EditMode='EditOnEnter'
$delayColumn=[Windows.Forms.DataGridViewTextBoxColumn]::new();$delayColumn.HeaderText='距前一步等待 ms';[void]$macroSteps.Columns.Add($delayColumn)
$macroKeyColumn=[Windows.Forms.DataGridViewComboBoxColumn]::new();$macroKeyColumn.HeaderText='遊戲按鍵';$macroKeyColumn.FlatStyle='Standard';foreach($key in $script:KeyIds.Keys){if($script:KeyIds[$key] -lt 16){[void]$macroKeyColumn.Items.Add($key)}};[void]$macroSteps.Columns.Add($macroKeyColumn)
$eventColumn=[Windows.Forms.DataGridViewComboBoxColumn]::new();$eventColumn.HeaderText='動作';$eventColumn.FlatStyle='Standard';[void]$eventColumn.Items.AddRange([object[]]@('按下','放開'));[void]$macroSteps.Columns.Add($eventColumn);$macroLayout.Controls.Add($macroSteps,0,4)
# Reuse the mapping grid's explicit dropdown colours.
$macroSteps.Add_EditingControlShowing($readableDropdown)
$macroStepToolbar=[Windows.Forms.FlowLayoutPanel]::new();$macroStepToolbar.AutoSize=$true;$macroStepToolbar.Dock='Fill';$macroLayout.Controls.Add($macroStepToolbar,0,5)
foreach($spec in @(@('macroTap','加入 A 按放'),@('macroRemoveStep','刪除步驟'),@('macroUp','上移'),@('macroDown','下移'))){$b=[Windows.Forms.Button]::new();$b.Text=$spec[1];$b.AutoSize=$true;$b.MinimumSize=[Drawing.Size]::new(95,34);Set-Variable -Name $spec[0] -Value $b;$macroStepToolbar.Controls.Add($b)}
$macroStatus=[Windows.Forms.Label]::new();$macroStatus.AutoSize=$true;$macroStatus.Dock='Fill';$macroStatus.Text='切換至本頁後讀取巨集。每個配置最多 10 組，共用 1632 位元組。';$macroLayout.Controls.Add($macroStatus,0,6)
$statusTip.SetToolTip($macroName,'最多 20 個 UTF-8 位元組；中文字通常每字 3 個位元組。')
$script:MacroState=$null;$script:MacroDrafts=[Collections.Generic.List[VaderMacro]]::new();$script:MacroSelected=-1;$script:MacroLoading=$false;$script:MacroDirty=$false;$script:MacroCurrentDirty=$false
$macroSave.Enabled=$false;$macroNew.Enabled=$false;$macroDelete.Enabled=$false;$macroFields.Enabled=$false;$macroSteps.Enabled=$false;$macroStepToolbar.Enabled=$false

function Get-MacroKeyName([byte]$id){foreach($key in $script:KeyIds.Keys){if($script:KeyIds[$key] -eq $id){return $key}};return "Key#$id"}
function Save-MacroDraft {
    if(-not $script:MacroCurrentDirty -or $script:MacroSelected -lt 0){return}
    [void]$macroSteps.EndEdit()
    $m=$script:MacroDrafts[$script:MacroSelected].Clone()
    $m.Trigger=[byte]$script:KeyIds[[string]$macroTrigger.SelectedItem];$m.Name=$macroName.Text;$m.Playback=[byte]($macroPlayback.SelectedIndex+1);$m.RepeatInterval=[int]$macroRepeat.Value;$m.Steps.Clear();$time=0
    foreach($row in $macroSteps.Rows){
        $delay=0;if(-not [int]::TryParse([string]$row.Cells[0].Value,[ref]$delay) -or $delay -lt 0 -or $delay -gt 65535){throw '每個等待時間必須是 0～65535 的整數。'}
        $time+=$delay;if($time -gt 65535){throw '巨集總長不能超過 65535 ms。'}
        $key=[string]$row.Cells[1].Value
        $id=if($script:KeyIds.Contains($key)){[int]$script:KeyIds[$key]}elseif($key -match '^Key#(\d+)$'){[int]$Matches[1]}else{throw '請選擇遊戲按鍵。'}
        $action=[string]$row.Cells[2].Value;if($action -notin @('按下','放開')){throw '請選擇按下或放開。'}
        $m.Steps.Add([VaderMacroStep]@{Time=$time;Key=[byte]$id;Event=[byte][int]($action -eq '按下')})
    }
    $script:MacroDrafts[$script:MacroSelected]=$m;$script:MacroCurrentDirty=$false
    $script:MacroLoading=$true
    try{$macroSelect.Items[$script:MacroSelected]="$(Get-MacroKeyName $m.Trigger) · $($m.Name)"}finally{$script:MacroLoading=$false}
}
function Update-MacroStatus {
    $used=0;foreach($m in $script:MacroDrafts){$used+=32+4*$m.Steps.Count}
    if($script:MacroSelected -ge 0 -and $script:MacroCurrentDirty){$used+=4*($macroSteps.Rows.Count-$script:MacroDrafts[$script:MacroSelected].Steps.Count)}
    $prefix=if($script:MacroDirty){'未儲存 · '}else{''}
    $macroStatus.Text="$prefix$($script:MacroDrafts.Count)/10 組 · $used/1632 位元組 · 等待時間在該步驟之前；結束前需放開所有按鍵。"
}
function Show-MacroDraft {
    $script:MacroLoading=$true
    try{
        $macroSteps.Rows.Clear();$selected=$script:MacroSelected -ge 0
        $macroFields.Enabled=$selected;$macroSteps.Enabled=$selected;$macroStepToolbar.Enabled=$selected;$macroDelete.Enabled=$selected
        if($selected){
            $m=$script:MacroDrafts[$script:MacroSelected];$macroTrigger.SelectedItem=Get-MacroKeyName $m.Trigger;$macroName.Text=$m.Name;$macroPlayback.SelectedIndex=if($m.Playback -in @(1,2,3)){$m.Playback-1}else{-1};$macroRepeat.Value=[Math]::Min(65534,$m.RepeatInterval)
            $previous=0
            foreach($step in $m.Steps){$key=Get-MacroKeyName $step.Key;if(-not $macroKeyColumn.Items.Contains($key)){[void]$macroKeyColumn.Items.Add($key)};[void]$macroSteps.Rows.Add(($step.Time-$previous),$key,$(if($step.Event -eq 1){'按下'}else{'放開'}));$previous=$step.Time}
        }else{$macroName.Text='';$macroTrigger.SelectedIndex=-1;$macroPlayback.SelectedIndex=-1;$macroRepeat.Value=0}
        $script:MacroCurrentDirty=$false;Update-MacroStatus
    } finally {$script:MacroLoading=$false}
}
function Update-MacroList([int]$select){
    $script:MacroLoading=$true
    try{$macroSelect.Items.Clear();foreach($m in $script:MacroDrafts){[void]$macroSelect.Items.Add("$(Get-MacroKeyName $m.Trigger) · $($m.Name)")};$macroSelect.SelectedIndex=$select;$script:MacroSelected=$select}finally{$script:MacroLoading=$false}
    Show-MacroDraft
}
$macroMarkDirty={if(-not $script:MacroLoading -and $script:MacroSelected -ge 0){$script:MacroDirty=$true;$script:MacroCurrentDirty=$true;Update-MacroStatus}}
$macroSteps.Add_CurrentCellDirtyStateChanged({if($macroSteps.IsCurrentCellDirty){[void]$macroSteps.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)}})
$macroSteps.Add_CellValueChanged($macroMarkDirty);$macroSteps.Add_RowsAdded($macroMarkDirty);$macroSteps.Add_RowsRemoved($macroMarkDirty)
$macroName.Add_TextChanged($macroMarkDirty);$macroTrigger.Add_SelectedIndexChanged($macroMarkDirty);$macroPlayback.Add_SelectedIndexChanged($macroMarkDirty);$macroRepeat.Add_ValueChanged($macroMarkDirty)
$macroSelect.Add_SelectedIndexChanged({
    if($script:MacroLoading){return};$next=$macroSelect.SelectedIndex
    try{Save-MacroDraft;$script:MacroSelected=$next;Show-MacroDraft}
    catch{$macroStatus.Text=$_.Exception.GetBaseException().Message;$script:MacroLoading=$true;$macroSelect.SelectedIndex=$script:MacroSelected;$script:MacroLoading=$false}
})
$reloadMacros={
    $macroReload.Enabled=$false;$macroSave.Enabled=$false;$macroNew.Enabled=$false;$form.UseWaitCursor=$true
    try{
        $state=Get-VaderMacroState;$script:MacroState=$state;$script:MacroDrafts.Clear();foreach($m in $state.Store.Macros){$script:MacroDrafts.Add($m.Clone())}
        $script:MacroDirty=$false;$script:MacroCurrentDirty=$false;Update-MacroList $(if($script:MacroDrafts.Count){0}else{-1});$macroSave.Enabled=$true;$macroNew.Enabled=$true
        $macroStatus.Text="配置 $($state.Profile+1) · $($state.Connection) · 巨集已讀取 · $($script:MacroDrafts.Count)/10 組"
    }catch{$script:MacroState=$null;$macroStatus.Text='讀取失敗：'+$_.Exception.GetBaseException().Message}
    finally{$macroReload.Enabled=$true;$form.UseWaitCursor=$false}
}
$macroReload.Add_Click({if($script:MacroDirty -and [Windows.Forms.MessageBox]::Show($form,'捨棄未儲存巨集，重新讀取？','重新讀取巨集','YesNo','Question') -ne 'Yes'){return};& $reloadMacros})
$macroNew.Add_Click({
    try{
        Save-MacroDraft;if($script:MacroDrafts.Count -ge 10){throw '每個配置最多 10 組巨集。'}
        $used=@($script:MacroDrafts|ForEach-Object Trigger);$key=@('M1','M2','M3','M4','LM','RM','C','Z','A','B','X','Y','LB','RB','L3','R3','LT','RT','Up','Down','Left','Right','View','Menu')|Where-Object {$script:KeyIds[$_] -notin $used}|Select-Object -First 1
        $m=[VaderMacro]::new();$m.Trigger=[byte]$script:KeyIds[$key];$m.Name="Macro $key";$m.Steps.Add([VaderMacroStep]@{Time=0;Key=4;Event=1});$m.Steps.Add([VaderMacroStep]@{Time=50;Key=4;Event=0})
        $script:MacroDrafts.Add($m);$script:MacroDirty=$true;Update-MacroList ($script:MacroDrafts.Count-1)
    }catch{$macroStatus.Text=$_.Exception.GetBaseException().Message}
})
$macroDelete.Add_Click({if($script:MacroSelected -ge 0){$script:MacroDrafts.RemoveAt($script:MacroSelected);$script:MacroCurrentDirty=$false;$script:MacroDirty=$true;Update-MacroList $(if($script:MacroDrafts.Count){0}else{-1})}})
$macroTap.Add_Click({[void]$macroSteps.EndEdit();[void]$macroSteps.Rows.Add($(if($macroSteps.Rows.Count){50}else{0}),'A','按下');[void]$macroSteps.Rows.Add(50,'A','放開')})
$macroRemoveStep.Add_Click({if($macroSteps.CurrentRow){$macroSteps.Rows.RemoveAt($macroSteps.CurrentRow.Index)}})
function Move-MacroStep([int]$direction){
    if(-not $macroSteps.CurrentRow){return};[void]$macroSteps.EndEdit();$index=$macroSteps.CurrentRow.Index;$next=$index+$direction;if($next -lt 0 -or $next -ge $macroSteps.Rows.Count){return}
    $values=[object[]]@($macroSteps.Rows[$index].Cells|ForEach-Object Value);$macroSteps.Rows.RemoveAt($index);$macroSteps.Rows.Insert($next,$values);$macroSteps.CurrentCell=$macroSteps.Rows[$next].Cells[0]
}
$macroUp.Add_Click({Move-MacroStep -1});$macroDown.Add_Click({Move-MacroStep 1})
$macroSave.Add_Click({
    $macroSave.Enabled=$false;$macroReload.Enabled=$false;$form.UseWaitCursor=$true
    try{
        Save-MacroDraft;$message=Set-VaderMacroState $script:MacroState ($script:MacroDrafts.ToArray())
        & $reloadMacros
        if($script:MacroState){$macroStatus.Text=if($message -eq '設定已相同，沒有重複寫入。'){$message}else{"配置 $($script:MacroState.Profile+1) 巨集已儲存、備份並驗證。"};$statusTip.SetToolTip($macroStatus,$message);& $reload}
    }catch{$macroStatus.Text=$_.Exception.GetBaseException().Message;$macroSave.Enabled=$true}
    finally{$macroReload.Enabled=$true;$form.UseWaitCursor=$false}
})
$tabs.Add_Selecting({param($sender,$eventArgs)
    if(($eventArgs.TabPage -eq $macroPage -and $script:DraftChanged) -or ($eventArgs.TabPage -eq $editor -and $script:MacroDirty)){$eventArgs.Cancel=$true;[void][Windows.Forms.MessageBox]::Show($form,'請先儲存目前頁面的修改，或重新讀取以捨棄修改，再切換編輯頁。','尚有未儲存修改','OK','Information')}
})
$tabs.Add_SelectedIndexChanged({if($tabs.SelectedTab -eq $macroPage -and -not $script:MacroState){& $reloadMacros}})
