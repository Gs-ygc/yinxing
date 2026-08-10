package com.yinxing.launcher.feature.home

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DefaultItemAnimator
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ItemTouchHelper
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.databinding.ActivityMainBinding
import com.yinxing.launcher.feature.phone.PhoneCallLauncher
import com.yinxing.launcher.feature.phone.PhoneContactManager
import com.yinxing.launcher.feature.phone.showPhoneCallFallbackDialog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    companion object {
        private const val STATE_PENDING_CALL_ID = "state_home_pending_call_id"
        private const val STATE_PENDING_CALL_NAME = "state_home_pending_call_name"
        private const val STATE_PENDING_CALL_NUMBER = "state_home_pending_call_number"
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var adapter: HomeAppAdapter
    private lateinit var itemMoveCallback: ItemMoveCallback
    private lateinit var headerController: WeatherHeaderController
    private lateinit var statusController: HomeStatusController
    private lateinit var trustedContactsController: HomeTrustedContactsController
    private lateinit var navigator: HomeNavigator
    private lateinit var viewModel: HomeViewModel
    private lateinit var phoneCallLauncher: PhoneCallLauncher
    private val timeTicker = TimeTicker()
    private var packageReceiverRegistered = false
    private var tickerJob: Job? = null
    private var fullyDrawnReported = false
    private var callFallbackDialog: AlertDialog? = null

    private val callPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> phoneCallLauncher.onPermissionResult(granted) }

    private val packageChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            viewModel.onPackageChanged()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        viewModel = ViewModelProvider(this, HomeViewModel.Factory(this))[HomeViewModel::class.java]
        navigator = HomeNavigator(this)
        phoneCallLauncher = PhoneCallLauncher(
            hasCallPermission = {
                ActivityCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
                    PackageManager.PERMISSION_GRANTED
            },
            requestPermission = {
                callPermissionLauncher.launch(Manifest.permission.CALL_PHONE)
            },
            launchIntent = ::startActivity,
            showFallback = ::showCallFallbackDialog,
            onCallLaunched = { contact -> recordCall(contact) }
        )
        restorePendingCall(savedInstanceState)
        headerController = WeatherHeaderController(binding)
        statusController = HomeStatusController(
            binding = binding,
            onRetry = viewModel::refreshApps,
            onOpenSettings = navigator::showCaregiverEntryDialog
        )
        trustedContactsController = HomeTrustedContactsController(binding.layoutTrustedCalls.root)
        setupBackPress()
        setupRecycler()
        setupActions()
        observeViewModel()
        registerPackageReceiver()
        playEntryAnimation()
        binding.recyclerHome.post { viewModel.refreshApps() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        startTimeTicker()
        viewModel.maybeRefreshWeather()
        viewModel.refreshTrustedContacts()
    }

    override fun onPause() {
        tickerJob?.cancel()
        tickerJob = null
        viewModel.cancelPendingWeatherRefresh()
        super.onPause()
    }

    override fun onDestroy() {
        callFallbackDialog?.setOnDismissListener(null)
        callFallbackDialog?.dismiss()
        callFallbackDialog = null
        if (packageReceiverRegistered) {
            unregisterReceiver(packageChangeReceiver)
        }
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        phoneCallLauncher.pendingContactOrNull?.let { contact ->
            outState.putString(STATE_PENDING_CALL_ID, contact.id)
            outState.putString(STATE_PENDING_CALL_NAME, contact.displayName)
            outState.putString(STATE_PENDING_CALL_NUMBER, contact.phoneNumber)
        }
        super.onSaveInstanceState(outState)
    }

    private fun setupBackPress() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                Toast.makeText(
                    this@MainActivity,
                    getString(R.string.home_toast_already_here),
                    Toast.LENGTH_SHORT
                ).show()
            }
        })
    }

    private fun setupRecycler() {
        val settings = viewModel.settings.value
        adapter = HomeAppAdapter(
            scope = lifecycleScope,
            lowPerformanceMode = settings.lowPerformanceMode,
            iconScale = settings.iconScale,
            onItemClick = navigator::openHomeItem,
            onOrderChanged = viewModel::saveAppOrder
        )
        binding.recyclerHome.layoutManager = GridLayoutManager(this, 2)
        binding.recyclerHome.setHasFixedSize(false)
        binding.recyclerHome.adapter = adapter
        itemMoveCallback = ItemMoveCallback(adapter, !settings.lowPerformanceMode)
        ItemTouchHelper(itemMoveCallback).also {
            it.attachToRecyclerView(binding.recyclerHome)
            adapter.setTouchHelper(it)
        }
        adapter.submitList(viewModel.homeUiState.value.items)
        applySettings(settings)
    }

    private fun setupActions() {
        binding.cardWeather.root.setOnClickListener { navigator.openWeatherEntry() }
        binding.btnFamilySettings.setOnClickListener { navigator.showCaregiverEntryDialog() }
        trustedContactsController.setOnCallClick(::makeCall)
        trustedContactsController.setOnOpenAllClick(navigator::openPhoneContacts)
    }

    private fun observeViewModel() {
        lifecycleScope.launch {
            viewModel.homeUiState.collect(::renderHomeState)
        }
        lifecycleScope.launch {
            viewModel.settings.collect(::applySettings)
        }
        lifecycleScope.launch {
            viewModel.weatherState.collect { state ->
                state?.let(headerController::renderWeather)
            }
        }
        lifecycleScope.launch {
            viewModel.trustedContacts.collect(trustedContactsController::render)
        }
    }

    private fun renderHomeState(state: HomeUiState) {
        adapter.submitList(state.items) {
            maybeReportFullyDrawn(state)
        }
        statusController.render(state)
    }

    private fun applySettings(settings: HomeSettingsState) {
        binding.recyclerHome.setItemViewCacheSize(if (settings.lowPerformanceMode) 4 else 10)
        binding.recyclerHome.itemAnimator = if (settings.lowPerformanceMode) null else DefaultItemAnimator()
        adapter.setLowPerformanceMode(settings.lowPerformanceMode)
        adapter.setIconScale(settings.iconScale)
        itemMoveCallback.setAnimateDrag(!settings.lowPerformanceMode)
        headerController.applyScale(settings.iconScale)
    }

    private fun startTimeTicker() {
        tickerJob?.cancel()
        tickerJob = lifecycleScope.launch {
            timeTicker.run { snapshot ->
                headerController.renderTime(snapshot, viewModel.settings.value.lowPerformanceMode)
            }
        }
    }

    private fun registerPackageReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(packageChangeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(packageChangeReceiver, filter)
        }
        packageReceiverRegistered = true
    }

    private fun maybeReportFullyDrawn(state: HomeUiState) {
        if (fullyDrawnReported || state is HomeUiState.Loading) {
            return
        }
        fullyDrawnReported = true
        binding.recyclerHome.post {
            reportFullyDrawn()
        }
    }

    private fun playEntryAnimation() {
        if (viewModel.settings.value.lowPerformanceMode) {
            return
        }
        binding.layoutHomeRoot.alpha = 0f
        binding.layoutHomeRoot.translationY = 18f
        binding.layoutHomeRoot.post {
            binding.layoutHomeRoot.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(240)
                .setInterpolator(DecelerateInterpolator())
                .start()
        }
    }

    private fun makeCall(contact: Contact) {
        if (callFallbackDialog?.isShowing == true) return
        phoneCallLauncher.makeCall(contact)
    }

    private fun recordCall(contact: Contact) {
        lifecycleScope.launch(Dispatchers.IO) {
            runCatching {
                PhoneContactManager.getInstance(applicationContext).incrementCallCount(contact.id)
            }
        }
    }

    private fun showCallFallbackDialog(contact: Contact, directCallFailed: Boolean) {
        if (isFinishing || isDestroyed) return
        callFallbackDialog?.dismiss()
        val dialog = showPhoneCallFallbackDialog(
            contact = contact,
            directCallFailed = directCallFailed
        ) { error ->
            Toast.makeText(
                this,
                getString(R.string.dial_failed, error.message.orEmpty()),
                Toast.LENGTH_SHORT
            ).show()
        }
        dialog.setOnDismissListener {
            if (callFallbackDialog === dialog) callFallbackDialog = null
        }
        callFallbackDialog = dialog
    }

    private fun restorePendingCall(savedInstanceState: Bundle?) {
        savedInstanceState
            ?.getString(STATE_PENDING_CALL_NUMBER)
            ?.takeIf { it.isNotBlank() }
            ?.let { number ->
                Contact(
                    id = savedInstanceState.getString(STATE_PENDING_CALL_ID).orEmpty(),
                    name = savedInstanceState.getString(STATE_PENDING_CALL_NAME)
                        ?.takeIf { it.isNotBlank() }
                        ?: getString(R.string.contact_name_placeholder),
                    phoneNumber = number
                )
            }
            ?.let(phoneCallLauncher::restorePendingContact)
    }
}
