package com.yinxing.launcher.feature.home

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.data.weather.WeatherState
import com.yinxing.launcher.databinding.ItemHomeHeaderBinding

/**
 * One full-span header keeps the elder-facing status and trusted calls in the same
 * virtualized RecyclerView as the application grid.
 */
class HomeHeaderAdapter(
    private val onOpenWeather: () -> Unit,
    private val onOpenCaregiver: () -> Unit,
    private val onRetryApps: () -> Unit,
    private val onCall: (Contact) -> Unit,
    private val onOpenAllCalls: () -> Unit
) : RecyclerView.Adapter<HomeHeaderAdapter.ViewHolder>() {
    private var holder: ViewHolder? = null
    private var homeState: HomeUiState? = null
    private var weatherState: WeatherState? = null
    private var trustedContacts: List<Contact> = emptyList()
    private var settings = HomeSettingsState(lowPerformanceMode = false, iconScale = 100)
    private var timeSnapshot: TimeSnapshot? = null

    override fun getItemCount(): Int = 1

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemHomeHeaderBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ViewHolder(binding).also { viewHolder ->
            binding.cardWeather.root.setOnClickListener { onOpenWeather() }
            binding.btnFamilySettings.setOnClickListener { onOpenCaregiver() }
            viewHolder.trustedContactsController.setOnCallClick(onCall)
            viewHolder.trustedContactsController.setOnOpenAllClick(onOpenAllCalls)
        }
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        this.holder = holder
        render(holder)
    }

    override fun onViewRecycled(holder: ViewHolder) {
        if (this.holder === holder) {
            this.holder = null
        }
        super.onViewRecycled(holder)
    }

    fun renderHomeState(state: HomeUiState) {
        homeState = state
        holder?.statusController?.render(state)
    }

    fun renderWeather(state: WeatherState) {
        weatherState = state
        holder?.weatherController?.renderWeather(state)
    }

    fun renderTrustedContacts(contacts: List<Contact>) {
        trustedContacts = contacts
        holder?.trustedContactsController?.render(contacts)
    }

    fun renderTime(snapshot: TimeSnapshot, lowPerformanceMode: Boolean) {
        timeSnapshot = snapshot
        holder?.weatherController?.renderTime(snapshot, lowPerformanceMode)
    }

    fun applySettings(settings: HomeSettingsState) {
        this.settings = settings
        holder?.weatherController?.applyScale(settings.iconScale)
        timeSnapshot?.let { snapshot ->
            holder?.weatherController?.renderTime(snapshot, settings.lowPerformanceMode)
        }
    }

    private fun render(holder: ViewHolder) {
        holder.weatherController.applyScale(settings.iconScale)
        timeSnapshot?.let { snapshot ->
            holder.weatherController.renderTime(snapshot, settings.lowPerformanceMode)
        }
        weatherState?.let(holder.weatherController::renderWeather)
        homeState?.let(holder.statusController::render)
        holder.trustedContactsController.render(trustedContacts)
    }

    inner class ViewHolder(binding: ItemHomeHeaderBinding) : RecyclerView.ViewHolder(binding.root) {
        val weatherController = WeatherHeaderController(binding)
        val statusController = HomeStatusController(
            binding = binding,
            onRetry = onRetryApps,
            onOpenSettings = onOpenCaregiver
        )
        val trustedContactsController = HomeTrustedContactsController(binding.layoutTrustedCalls.root)
    }
}
