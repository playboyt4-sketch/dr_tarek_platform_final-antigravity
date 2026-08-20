# ================= خطوة 1أ: إضافة حقول الإيقاف التأديبي =================

function Edit-File($path, $old, $new, $label) {
    if (-not (Test-Path $path)) {
        Write-Host "ERROR: File not found: $path" -ForegroundColor Red
        return $false
    }
    $content = Get-Content -Path $path -Raw
    if (-not $content.Contains($old)) {
        Write-Host "ERROR: Anchor text not found in $path for [$label]. No changes made. Send a screenshot of this file." -ForegroundColor Red
        return $false
    }
    $content = $content.Replace($old, $new)
    Set-Content -Path $path -Value $content -Encoding utf8 -NoNewline
    Write-Host "OK: $label updated in $path" -ForegroundColor Green
    return $true
}

# --- ملف 1: student_subscription.dart (إضافة الحقول) ---
$p1 = "lib\features\membership\domain\entities\student_subscription.dart"
$old1 = "  final String? previousPlanId;"
$new1 = "  final String? previousPlanId;`r`n  final bool manuallyDisabled;`r`n  final String? disabledBy;`r`n  final DateTime? disabledAt;`r`n  final String? disabledReason;"
Edit-File $p1 $old1 $new1 "Entity fields"

$old2 = "    required this.previousPlanId,`r`n  });"
$new2 = "    required this.previousPlanId,`r`n    this.manuallyDisabled = false,`r`n    this.disabledBy,`r`n    this.disabledAt,`r`n    this.disabledReason,`r`n  });"
Edit-File $p1 $old2 $new2 "Entity constructor"

# --- ملف 2: membership_remote_data_source.dart (قراءة الحقول من Firestore) ---
$p2 = "lib\features\membership\data\datasources\membership_remote_data_source.dart"
$old3 = "      previousPlanId: data['previous_plan_id'] as String?,`r`n    );`r`n  }"
$new3 = "      previousPlanId: data['previous_plan_id'] as String?,`r`n      manuallyDisabled: data['manually_disabled'] == true,`r`n      disabledBy: data['disabled_by'] as String?,`r`n      disabledAt: (data['disabled_at'] as Timestamp?)?.toDate(),`r`n      disabledReason: data['disabled_reason'] as String?,`r`n    );`r`n  }"
Edit-File $p2 $old3 $new3 "Firestore mapping"

# --- ملف 3: entitlement_resolver.dart (استخدام الحقل في القرار) ---
$p3 = "lib\features\membership\domain\services\entitlement_resolver.dart"
$old4 = "    if (subscription.isFrozen) return false;"
$new4 = "    if (subscription.isFrozen) return false;`r`n    if (subscription.manuallyDisabled) return false;"
Edit-File $p3 $old4 $new4 "Entitlement check"

Write-Host ""
Write-Host "===== انتهت الخطوة. شغّل الآن: flutter analyze =====" -ForegroundColor Cyan
