$p1 = "lib\features\membership\domain\entities\student_subscription.dart"
$content = Get-Content -Path $p1 -Raw

$oldCrLf = "    required this.previousPlanId,`r`n  });"
$oldLf   = "    required this.previousPlanId,`n  });"
$newCrLf = "    required this.previousPlanId,`r`n    this.manuallyDisabled = false,`r`n    this.disabledBy,`r`n    this.disabledAt,`r`n    this.disabledReason,`r`n  });"
$newLf   = "    required this.previousPlanId,`n    this.manuallyDisabled = false,`n    this.disabledBy,`n    this.disabledAt,`n    this.disabledReason,`n  });"

if ($content.Contains($oldCrLf)) {
    $content = $content.Replace($oldCrLf, $newCrLf)
    Set-Content -Path $p1 -Value $content -Encoding utf8 -NoNewline
    Write-Host "OK: Entity constructor updated (CRLF variant)" -ForegroundColor Green
}
elseif ($content.Contains($oldLf)) {
    $content = $content.Replace($oldLf, $newLf)
    Set-Content -Path $p1 -Value $content -Encoding utf8 -NoNewline
    Write-Host "OK: Entity constructor updated (LF variant)" -ForegroundColor Green
}
else {
    Write-Host "ERROR: still not found. Send screenshot again." -ForegroundColor Red
}
