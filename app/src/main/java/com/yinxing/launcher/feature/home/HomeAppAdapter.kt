package com.yinxing.launcher.feature.home

import android.content.Context
import android.graphics.Bitmap
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.cardview.widget.CardView
import androidx.lifecycle.LifecycleCoroutineScope
import androidx.recyclerview.widget.AsyncDifferConfig
import androidx.recyclerview.widget.AsyncListDiffer
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.ListUpdateCallback
import androidx.recyclerview.widget.RecyclerView
import com.yinxing.launcher.R
import com.yinxing.launcher.common.media.MediaThumbnailLoader
import java.util.Collections
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class HomeAppAdapter(
    private val scope: LifecycleCoroutineScope,
    private var lowPerformanceMode: Boolean,
    private var iconScale: Int = 100,
    private val onItemClick: (HomeAppItem) -> Unit,
    private val onOrderChanged: (List<HomeAppItem>) -> Unit,
    private val loadAppIcon: suspend (Context, String, Int) -> Bitmap? =
        MediaThumbnailLoader::loadAppIcon
) : RecyclerView.Adapter<RecyclerView.ViewHolder>(), ItemTouchHelperAdapter {
    companion object {
        const val VIEW_TYPE_APP = 0
        private const val PAYLOAD_UI = "payload_ui"

        private val DiffCallback = object : DiffUtil.ItemCallback<HomeAppItem>() {
            override fun areItemsTheSame(oldItem: HomeAppItem, newItem: HomeAppItem) =
                oldItem.stableId == newItem.stableId

            override fun areContentsTheSame(oldItem: HomeAppItem, newItem: HomeAppItem) =
                oldItem == newItem
        }
    }

    private var suppressDifferUpdates = false
    private val differ = AsyncListDiffer(
        object : ListUpdateCallback {
            override fun onInserted(position: Int, count: Int) {
                if (!suppressDifferUpdates) notifyItemRangeInserted(position, count)
            }

            override fun onRemoved(position: Int, count: Int) {
                if (!suppressDifferUpdates) notifyItemRangeRemoved(position, count)
            }

            override fun onMoved(fromPosition: Int, toPosition: Int) {
                if (!suppressDifferUpdates) notifyItemMoved(fromPosition, toPosition)
            }

            override fun onChanged(position: Int, count: Int, payload: Any?) {
                if (!suppressDifferUpdates) notifyItemRangeChanged(position, count, payload)
            }
        },
        AsyncDifferConfig.Builder(DiffCallback).build()
    )
    private var touchHelper: ItemTouchHelper? = null
    private var dragItems: MutableList<HomeAppItem>? = null
    private var dragChanged = false
    private var dragCommitInFlight = false
    private var pendingSubmission: PendingSubmission? = null

    val currentList: List<HomeAppItem>
        get() = differ.currentList

    init {
        setHasStableIds(true)
    }

    fun setTouchHelper(helper: ItemTouchHelper) {
        touchHelper = helper
    }

    fun setLowPerformanceMode(enabled: Boolean) {
        if (lowPerformanceMode == enabled) return
        lowPerformanceMode = enabled
        notifyItemRangeChanged(0, itemCount, PAYLOAD_UI)
    }

    fun setIconScale(scale: Int) {
        if (iconScale == scale) return
        iconScale = scale
        notifyItemRangeChanged(0, itemCount, PAYLOAD_UI)
    }

    fun submitList(items: List<HomeAppItem>, commitCallback: (() -> Unit)? = null) {
        if (dragItems != null || dragCommitInFlight) {
            pendingSubmission = PendingSubmission(items, commitCallback)
            return
        }
        differ.submitList(items) {
            commitCallback?.invoke()
        }
    }

    class AppViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val card: CardView = view.findViewById(R.id.card_item)
        val icon: ImageView = view.findViewById(R.id.icon)
        val name: TextView = view.findViewById(R.id.name)
        var iconJob: Job? = null
        var boundItem: HomeAppItem? = null
        var boundStableId: Long = RecyclerView.NO_ID
        var uiKey: Int = Int.MIN_VALUE
    }

    override fun getItemCount(): Int = displayedItems().size

    override fun getItemViewType(position: Int): Int = VIEW_TYPE_APP

    override fun getItemId(position: Int): Long = itemAt(position).stableId

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return AppViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.item_home_app, parent, false)
        )
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val item = itemAt(position)
        if (holder is AppViewHolder) {
            holder.itemView.animate().cancel()
            holder.itemView.alpha = 1f
            holder.itemView.translationY = 0f
            applyUi(holder)
            bindApp(holder, item)
        }
    }

    override fun onBindViewHolder(
        holder: RecyclerView.ViewHolder,
        position: Int,
        payloads: MutableList<Any>
    ) {
        if (holder is AppViewHolder && payloads.contains(PAYLOAD_UI)) {
            applyUi(holder)
            holder.boundItem
                ?.takeIf { it.type == HomeAppItem.Type.APP }
                ?.let { item -> loadApplicationIcon(holder, item, showPlaceholder = false) }
            return
        }
        super.onBindViewHolder(holder, position, payloads)
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        if (holder is AppViewHolder) {
            holder.iconJob?.cancel()
            holder.iconJob = null
            holder.boundItem = null
            holder.boundStableId = RecyclerView.NO_ID
        }
        super.onViewRecycled(holder)
    }

    private fun displayedItems(): List<HomeAppItem> = dragItems ?: currentList

    private fun itemAt(position: Int): HomeAppItem = displayedItems()[position]

    private fun itemAtOrNull(position: Int): HomeAppItem? = displayedItems().getOrNull(position)

    private fun applyUi(holder: AppViewHolder) {
        val context = holder.itemView.context
        val uiKey = iconScale * 10 + if (lowPerformanceMode) 1 else 0
        if (holder.uiKey == uiKey) {
            return
        }
        holder.uiKey = uiKey
        holder.card.cardElevation = context.dpToPx(if (lowPerformanceMode) 2 else 6).toFloat()
        val baseIconDp = if (lowPerformanceMode) 80 else 96
        val iconSize = context.dpToPx((baseIconDp * iconScale / 100f).toInt().coerceAtLeast(48))
        val iconLp = holder.icon.layoutParams
        if (iconLp.width != iconSize || iconLp.height != iconSize) {
            iconLp.width = iconSize
            iconLp.height = iconSize
            holder.icon.layoutParams = iconLp
        }
        val basePadDp = if (lowPerformanceMode) 12 else 16
        val pad = context.dpToPx((basePadDp * iconScale / 100f).toInt().coerceAtLeast(8))
        if (holder.icon.paddingLeft != pad) {
            holder.icon.setPadding(pad, pad, pad, pad)
        }
        val cardMinHeight = context.dpToPx((200 * iconScale / 100f).toInt().coerceAtLeast(120))
        val cardLp = holder.card.layoutParams
        if (cardLp.height != ViewGroup.LayoutParams.WRAP_CONTENT) {
            cardLp.height = ViewGroup.LayoutParams.WRAP_CONTENT
            holder.card.layoutParams = cardLp
        }
        holder.card.minimumHeight = cardMinHeight
        val content = holder.card.findViewById<View>(R.id.layout_app_content)
        content.minimumHeight = cardMinHeight
        val contentLp = content.layoutParams
        if (contentLp.height != ViewGroup.LayoutParams.WRAP_CONTENT) {
            contentLp.height = ViewGroup.LayoutParams.WRAP_CONTENT
            content.layoutParams = contentLp
        }
        holder.name.textSize = (24f * iconScale / 100f).coerceAtLeast(16f)
    }

    private fun bindApp(holder: AppViewHolder, item: HomeAppItem) {
        holder.boundItem = item
        holder.boundStableId = item.stableId
        holder.name.text = item.appName
        holder.card.contentDescription = item.appName
        holder.icon.setBackgroundResource(
            when (item.type) {
                HomeAppItem.Type.PHONE -> R.drawable.icon_background_phone
                HomeAppItem.Type.WECHAT_VIDEO -> R.drawable.icon_background_wechat
                else -> R.drawable.icon_background
            }
        )
        holder.iconJob?.cancel()
        if (item.type == HomeAppItem.Type.APP) {
            loadApplicationIcon(holder, item, showPlaceholder = true)
        } else {
            holder.iconJob = null
            holder.icon.setImageResource(item.iconResId ?: android.R.drawable.sym_def_app_icon)
        }
        holder.icon.setOnLongClickListener(null)
        holder.card.setOnLongClickListener(null)
        val clickListener = View.OnClickListener { onItemClick(item) }
        holder.card.setOnClickListener(clickListener)
        holder.itemView.setOnClickListener(clickListener)
        holder.icon.setOnClickListener(clickListener)
        holder.name.setOnClickListener(clickListener)
        if (item.type == HomeAppItem.Type.APP) {
            holder.icon.setOnLongClickListener {
                touchHelper?.startDrag(holder)
                true
            }
        }
    }

    private fun loadApplicationIcon(
        holder: AppViewHolder,
        item: HomeAppItem,
        showPlaceholder: Boolean
    ) {
        if (showPlaceholder) {
            holder.icon.setImageResource(android.R.drawable.sym_def_app_icon)
        }
        holder.iconJob?.cancel()
        val context = holder.itemView.context
        val iconSize = holder.icon.layoutParams.width.coerceAtLeast(1)
        holder.iconJob = scope.launch {
            val bitmap = loadAppIcon(context, item.packageName, iconSize)
            if (holder.boundStableId == item.stableId && bitmap != null) {
                holder.icon.setImageBitmap(bitmap)
            }
        }
    }

    override fun canMoveItem(position: Int): Boolean =
        itemAtOrNull(position)?.type == HomeAppItem.Type.APP

    override fun onDragStarted(position: Int) {
        if (!canMoveItem(position) || dragItems != null) {
            return
        }
        dragItems = currentList.toMutableList()
        dragChanged = false
    }

    override fun onItemMove(fromPosition: Int, toPosition: Int): Boolean {
        if (!canMoveItem(fromPosition) || !canMoveItem(toPosition)) return false
        val reordered = dragItems ?: currentList.toMutableList().also {
            dragItems = it
            dragChanged = false
        }
        if (fromPosition !in reordered.indices || toPosition !in reordered.indices) {
            return false
        }
        if (fromPosition < toPosition) {
            for (index in fromPosition until toPosition) Collections.swap(reordered, index, index + 1)
        } else {
            for (index in fromPosition downTo toPosition + 1) Collections.swap(reordered, index, index - 1)
        }
        dragChanged = true
        notifyItemMoved(fromPosition, toPosition)
        return true
    }

    override fun onDragFinished() {
        val reordered = dragItems ?: return
        if (!dragChanged) {
            dragItems = null
            applyPendingSubmission()
            return
        }
        val finalItems = reordered.toList()
        dragChanged = false
        dragCommitInFlight = true
        suppressDifferUpdates = true
        differ.submitList(finalItems) {
            suppressDifferUpdates = false
            dragItems = null
            try {
                onOrderChanged(finalItems)
            } finally {
                dragCommitInFlight = false
                applyPendingSubmission()
            }
        }
    }

    private fun applyPendingSubmission() {
        val pending = pendingSubmission ?: return
        pendingSubmission = null
        submitList(pending.items, pending.commitCallback)
    }

    private data class PendingSubmission(
        val items: List<HomeAppItem>,
        val commitCallback: (() -> Unit)?
    )

    private fun android.content.Context.dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).toInt()
}
