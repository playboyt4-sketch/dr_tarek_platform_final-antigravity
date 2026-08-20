function Edit-File($path, $oldCrLf, $oldLf, $newCrLf, $newLf, $label) {
    if (-not (Test-Path $path)) {
        Write-Host "ERROR: File not found: $path" -ForegroundColor Red
        return $false
    }
    $content = Get-Content -Path $path -Raw
    if ($content.Contains($oldCrLf)) {
        $content = $content.Replace($oldCrLf, $newCrLf)
        Set-Content -Path $path -Value $content -Encoding utf8 -NoNewline
        Write-Host "OK: $label (CRLF)" -ForegroundColor Green
        return $true
    }
    elseif ($content.Contains($oldLf)) {
        $content = $content.Replace($oldLf, $newLf)
        Set-Content -Path $path -Value $content -Encoding utf8 -NoNewline
        Write-Host "OK: $label (LF)" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "ERROR: Anchor not found for [$label] in $path. No changes made. Send a screenshot." -ForegroundColor Red
        return $false
    }
}

$p = "functions\src\index.ts"

# --- تعديل 1: إضافة فحص الإيقاف التأديبي داخل assertSubjectAccess ---
$oldCrLf1 = "  if (subscription.is_frozen === true) throw new HttpsError(`"permission-denied`", `"Subscription is frozen.`");"
$oldLf1   = $oldCrLf1
$newCrLf1 = "  if (subscription.is_frozen === true) throw new HttpsError(`"permission-denied`", `"Subscription is frozen.`");`r`n  if (subscription.manually_disabled === true) throw new HttpsError(`"permission-denied`", `"Subscription is disciplinarily disabled by the Teacher.`");"
$newLf1   = "  if (subscription.is_frozen === true) throw new HttpsError(`"permission-denied`", `"Subscription is frozen.`");`n  if (subscription.manually_disabled === true) throw new HttpsError(`"permission-denied`", `"Subscription is disciplinarily disabled by the Teacher.`");"
Edit-File $p $oldCrLf1 $oldLf1 $newCrLf1 $newLf1 "assertSubjectAccess disciplinary check"

# --- تعديل 2: إضافة دالة setSubscriptionDisciplinaryStatus في نهاية الملف ---
$marker = "export const setSubjectAccess = onCall(async (request) => {"
$content2 = Get-Content -Path $p -Raw
if ($content2.Contains($marker) -and -not $content2.Contains("setSubscriptionDisciplinaryStatus")) {
    $newFunction = @"


export const setSubscriptionDisciplinaryStatus = onCall(async (request) => {
  const teacherId = requireTeacher(request);
  const subscriptionId = getString(request.data?.subscriptionId);
  const disabled = request.data?.disabled;
  const reason = getString(request.data?.reason);
  if (!subscriptionId || typeof disabled !== "boolean") {
    throw new HttpsError("invalid-argument", "subscriptionId and disabled are required.");
  }

  const subscriptionRef = db.collection("subscriptions").doc(subscriptionId);
  const auditRef = db.collection("admin_audit_log").doc();

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(subscriptionRef);
    if (!snap.exists) throw new HttpsError("not-found", "Subscription not found.");
    const previous = dataOf(snap.data());

    transaction.update(subscriptionRef, {
      manually_disabled: disabled,
      disabled_by: disabled ? teacherId : null,
      disabled_at: disabled ? FieldValue.serverTimestamp() : null,
      disabled_reason: disabled ? (reason ?? null) : null,
      updated_at: FieldValue.serverTimestamp(),
    });

    transaction.set(auditRef, {
      action: disabled ? "disciplinary_disable" : "disciplinary_enable",
      entity: "subscription",
      target_id: subscriptionId,
      student_id: previous.student_id ?? null,
      subject_id: previous.subject_id ?? null,
      reason: reason ?? null,
      actor_id: teacherId,
      created_at: FieldValue.serverTimestamp(),
    });
  });

  return {success: true};
});
"@
    $content2 = $content2 + $newFunction
    Set-Content -Path $p -Value $content2 -Encoding utf8 -NoNewline
    Write-Host "OK: setSubscriptionDisciplinaryStatus function appended" -ForegroundColor Green
}
elseif ($content2.Contains("setSubscriptionDisciplinaryStatus")) {
    Write-Host "SKIPPED: setSubscriptionDisciplinaryStatus already exists" -ForegroundColor Yellow
}
else {
    Write-Host "ERROR: Marker function setSubjectAccess not found. Send a screenshot." -ForegroundColor Red
}

Write-Host ""
Write-Host "===== انتهت الخطوة. شغّل الآن: cd functions ; npm run build ; cd .. =====" -ForegroundColor Cyan
