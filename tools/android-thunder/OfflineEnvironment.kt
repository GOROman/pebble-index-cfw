package poc.ringclick

import android.content.Context
import com.wtlp.haversinesatellitelibrary.*
import com.wtlp.haversinesatellitelibrary.operations.HaversineCollectionTransferCallback
import com.wtlp.haversinesatellitelibrary.operations.TelestoStoredCollectionIndexes

/** Native BLE environment with all remote updates and collection transfers disabled. */
fun offlineEnvironment(context: Context, address: String): HaversineEnvironment {
    val env = HaversineEnvironment(
        context.applicationContext,
        HaversineEnvironment.ApplicationHardwareVersion(11, 0),
    )
    env.cache = object : HaversineSatelliteCacheType {
        override fun fetchCachedState(id: HaversineSatelliteId): HaversineSatelliteCacheableState? = null
        override fun cacheState(state: HaversineSatelliteCacheableState, id: HaversineSatelliteId) {}
    }
    env.permissionsDelegate = object : HaversinePermissionsDelegate {
        override fun shouldHandleAdvertisement(advertisement: HaversineAdvertisement) = advertisement.id.rawValue.replace(":", "").equals(address.replace(":", ""), ignoreCase = true)
        override fun shouldHandleSatellite(satellite: HaversineSatellite) = satellite.id?.rawValue?.replace(":", "")?.equals(address.replace(":", ""), ignoreCase = true) == true
        override fun shouldTransferCollections(satellite: HaversineSatellite) = false
    }
    env.debugDelegate = object : HaversineDebugDelegate {
        override fun handleHaversineDebugInfo(info: HaversineDebugInfo, satellite: HaversineSatellite) {}
        override fun shouldReadRxRSSI(satellite: HaversineSatellite) = false
        override fun handleRxRSSI(rssi: Float, satellite: HaversineSatellite) {}
    }
    env.hacksDelegate = object : HaversineHacksDelegate {
        override fun shouldWipeCollectionsBeforeTransfer(satellite: HaversineSatellite) = false
        override fun wipedCollectionsBeforeTransfer(satellite: HaversineSatellite) {}
    }
    env.transferDelegate = object : HaversineCollectionTransferCallback {
        override fun firstCollectionToTransferInRange(indexes: TelestoStoredCollectionIndexes, satellite: HaversineSatellite) = Int.MAX_VALUE
        override fun willTransferCollectionsInRange(indexes: TelestoStoredCollectionIndexes, satellite: HaversineSatellite) {}
        override fun collectionTransferDidFinish(data: ByteArray, count: Int, satellite: HaversineSatellite) {}
        override fun collectionTransferDidFail(error: HaversineException, count: Int, satellite: HaversineSatellite) {}
    }
    env.updateDelegate = object : HaversineUpdateDelegate {
        override fun getFirmwareUpdate(satellite: HaversineSatellite): HaversineEnvironment.FirmwareUpdate? = null
        override fun willUpdateFirmware(satellite: HaversineSatellite, update: HaversineEnvironment.FirmwareUpdate) {}
        override fun didUpdateFirmware(satellite: HaversineSatellite, update: HaversineEnvironment.FirmwareUpdate, success: Boolean) {}
        override fun getSensorConfigUpdate(satellite: HaversineSatellite): HaversineEnvironment.SensorConfigUpdate? = null
    }
    return env
}
