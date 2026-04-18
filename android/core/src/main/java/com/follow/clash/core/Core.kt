package com.follow.clash.core

import android.content.Context
import androidx.annotation.Keep
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.URL
import java.util.Collections
import java.util.Locale

data object Core {
    @Volatile
    private var appContext: Context? = null

    private external fun startTun(
        fd: Int,
        cb: TunInterface,
        stack: String,
        address: String,
        dns: String,
    )

    external fun forceGC(
    )

    external fun updateDNS(
        dns: String,
    )

    fun initContext(context: Context) {
        appContext = context.applicationContext
    }

    private fun parseInetSocketAddress(address: String): InetSocketAddress {
        val url = URL("https://$address")

        return InetSocketAddress(InetAddress.getByName(url.host), url.port)
    }

    fun startTun(
        fd: Int,
        protect: (Int) -> Boolean,
        resolverProcess: (protocol: Int, source: InetSocketAddress, target: InetSocketAddress, uid: Int) -> String,
        stack: String,
        address: String,
        dns: String,
    ) {
        startTun(
            fd,
            object : TunInterface {
                override fun protect(fd: Int) {
                    protect(fd)
                }

                override fun resolverProcess(
                    protocol: Int,
                    source: String,
                    target: String,
                    uid: Int
                ): String {
                    return resolverProcess(
                        protocol,
                        parseInetSocketAddress(source),
                        parseInetSocketAddress(target),
                        uid,
                    )
                }
            },
            stack,
            address,
            dns
        )
    }

    external fun suspended(
        suspended: Boolean,
    )

    private external fun invokeAction(
        data: String,
        cb: InvokeInterface
    )

    fun invokeAction(
        data: String,
        cb: (result: String?) -> Unit
    ) {
        invokeAction(
            data,
            object : InvokeInterface {
                override fun onResult(result: String?) {
                    cb(result)
                }
            },
        )
    }

    private external fun setEventListener(cb: InvokeInterface?)

    fun callSetEventListener(
        cb: ((result: String?) -> Unit)?
    ) {
        when (cb != null) {
            true -> setEventListener(
                object : InvokeInterface {
                    override fun onResult(result: String?) {
                        cb(result)
                    }
                },
            )

            false -> setEventListener(null)
        }
    }

    fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        cb: (result: String?) -> Unit,
    ) {
        quickSetup(
            initParamsString,
            setupParamsString,
            object : InvokeInterface {
                override fun onResult(result: String?) {
                    cb(result)
                }
            },
        )
    }

    private external fun quickSetup(
        initParamsString: String,
        setupParamsString: String,
        cb: InvokeInterface
    )

    @Keep
    @JvmStatic
    fun getNetworkInterfacesJson(): String {
        val result = JSONArray()
        val interfaces = runCatching {
            val enumeration = NetworkInterface.getNetworkInterfaces()
            if (enumeration == null) {
                emptyList<NetworkInterface>()
            } else {
                Collections.list(enumeration)
            }
        }.getOrDefault(emptyList())

        interfaces.forEach { networkInterface ->
            val item = JSONObject()
            item.put("index", networkInterface.index)
            item.put("name", networkInterface.name ?: "")
            item.put("mtu", runCatching { networkInterface.mtu }.getOrDefault(0))
            item.put(
                "hardwareAddr",
                runCatching { networkInterface.hardwareAddress?.toHexMac() ?: "" }.getOrDefault("")
            )
            item.put("isUp", runCatching { networkInterface.isUp }.getOrDefault(false))
            item.put(
                "isLoopback",
                runCatching { networkInterface.isLoopback }.getOrDefault(false)
            )
            item.put(
                "isPointToPoint",
                runCatching { networkInterface.isPointToPoint }.getOrDefault(false)
            )
            item.put(
                "supportsMulticast",
                runCatching { networkInterface.supportsMulticast() }.getOrDefault(false)
            )

            val addrs = JSONArray()
            runCatching { networkInterface.interfaceAddresses ?: emptyList() }.getOrDefault(
                emptyList()
            ).forEach { interfaceAddress ->
                val address = interfaceAddress.address?.hostAddress
                    ?.substringBefore('%')
                    ?.trim()
                    .orEmpty()
                if (address.isEmpty()) {
                    return@forEach
                }
                addrs.put(
                    JSONObject().apply {
                        put("address", address)
                        put("prefixLength", interfaceAddress.networkPrefixLength.toInt())
                    }
                )
            }
            item.put("addrs", addrs)
            result.put(item)
        }

        return result.toString()
    }

    external fun stopTun()

    external fun getTraffic(onlyStatisticsProxy: Boolean): String

    external fun getTotalTraffic(onlyStatisticsProxy: Boolean): String

    init {
        System.loadLibrary("core")
    }
}

private fun ByteArray.toHexMac(): String {
    return joinToString(":") { String.format(Locale.US, "%02x", it.toInt() and 0xff) }
}
