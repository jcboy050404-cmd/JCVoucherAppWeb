package com.example.voucherapps

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.jc.voucherapps/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendSms") {
                val phone = call.argument<String>("phone")
                val message = call.argument<String>("message")

                if (!phone.isNullOrEmpty() && !message.isNullOrEmpty()) {
                    Thread {
                        val ok = sendSmsWithConfirmation(phone, message)
                        runOnUiThread {
                            if (ok) {
                                result.success(true)
                            } else {
                                result.error("SMS_FAILED", "SMS was not delivered to the radio", null)
                            }
                        }
                    }.start()
                } else {
                    result.error("INVALID_ARGS", "Phone and message are required", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Sends an SMS (single or multipart) and waits for Android's
     * ACTION_SMS_SENT broadcast for EVERY part before reporting success.
     *
     * This replaces the previous fire-and-forget call that returned `true`
     * instantly even when the message failed to reach the radio (no SIM,
     * no credit, invalid number, radio off). We now block on a
     * CountDownLatch with a generous per-batch timeout so the Dart side only
     * counts the message as "sent" when the platform actually accepted it.
     *
     * Returns true only if every part reported RESULT_OK.
     */
    private fun sendSmsWithConfirmation(phone: String, message: String): Boolean {
        val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applicationContext.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        val parts = smsManager.divideMessage(message)
        val partCount = parts.size

        // One latch tick per part; counted down as each SENT broadcast arrives.
        val latch = CountDownLatch(partCount)
        // 0 = unknown/pending, positive = at least one part failed.
        var failedParts = 0

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK) {
                    synchronized(this) { failedParts++ }
                }
                latch.countDown()
            }
        }

        // Mutable mutable list of sent PendingIntents, one per part.
        val sentIntents = ArrayList<PendingIntent>(partCount)
        val filter = IntentFilter("com.jc.voucherapps.SMS_SENT")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        try {
            // Register first so we never miss a (very fast) broadcast.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(receiver, filter)
            }

            for (i in 0 until partCount) {
                val sentIntent = Intent("com.jc.voucherapps.SMS_SENT").setPackage(packageName)
                sentIntents.add(PendingIntent.getBroadcast(this, i, sentIntent, flags))
            }

            if (partCount > 1) {
                smsManager.sendMultipartTextMessage(
                    phone, null, parts, sentIntents, null
                )
            } else {
                smsManager.sendTextMessage(
                    phone, null, message, sentIntents[0], null
                )
            }

            // Wait for all parts to be dispatched by the radio. 25s is well
            // beyond typical send time but bounded so we never hang forever.
            val allArrived = latch.await(25, TimeUnit.SECONDS)
            return allArrived && failedParts == 0
        } catch (e: Exception) {
            return false
        } finally {
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
        }
    }
}
