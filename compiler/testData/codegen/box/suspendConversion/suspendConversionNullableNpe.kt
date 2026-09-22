// ISSUE: KT-89451
// WITH_COROUTINES
class C {
    fun run() = ""
}

suspend fun observeAsValue(f: (suspend () -> String)?) {
    if (f == null) return
    f().length
}


fun box(): String = helpers.runBlocking {
    val b: C? = null
    observeAsValue(if (b == null) null else b::run)
    "OK"
}
