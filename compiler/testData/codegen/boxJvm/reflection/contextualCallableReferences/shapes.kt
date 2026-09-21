// LANGUAGE: +ContextParameters +CallableReferencesToContextual
// TARGET_BACKEND: JVM
// WITH_REFLECT
// ISSUE: KT-86452

import kotlin.reflect.KFunction
import kotlin.reflect.KParameter

context(c: String)
fun topFun(): String = "$c-topFun"

context(c: String)
fun withDefault(x: Int = 7): String = "$c-$x"

context(c: String)
fun twoArgs(first: Int, second: String): String = "$c-$first-$second"

class Cls {
    context(c: String)
    fun member(): String = "$c-member"
}

context(c: String)
val topProp: String get() = "$c-topProp"

var storage: String = ""

context(c: String, b: Boolean)
var twoCtxProp: String
    get() = storage
    set(value) { storage = "$c-$b-$value" }

fun box(): String {
    context("ctx") {
        val tf = ::topFun
        if (tf.call() != "ctx-topFun") return "FAIL 1: ${tf.call()}"
        if (tf.parameters.isNotEmpty()) return "FAIL 2: ${tf.parameters.map { it.kind }}"

        val tp = ::topProp
        if (tp.getter.call() != "ctx-topProp") return "FAIL 3: ${tp.getter.call()}"
        if (tp.getter.parameters.isNotEmpty()) return "FAIL 4: ${tp.getter.parameters.map { it.kind }}"

        val wd = ::withDefault
        if (wd.parameters.size != 1 || wd.parameters[0].kind != KParameter.Kind.VALUE) return "FAIL 5: ${wd.parameters.map { it.kind }}"
        if (wd.parameters[0].name != "x") return "FAIL 6: ${wd.parameters[0].name}"
        if (wd.callBy(emptyMap()) != "ctx-7") return "FAIL 7: ${wd.callBy(emptyMap())}"
        if (wd.callBy(mapOf(wd.parameters[0] to 5)) != "ctx-5") return "FAIL 8: ${wd.callBy(mapOf(wd.parameters[0] to 5))}"

        val ta = ::twoArgs
        if (ta.parameters.map { it.kind } != listOf(KParameter.Kind.VALUE, KParameter.Kind.VALUE)) return "FAIL 9: ${ta.parameters.map { it.kind }}"
        if (ta.parameters.map { it.name } != listOf("first", "second")) return "FAIL 10: ${ta.parameters.map { it.name }}"
        if (ta.call(3, "Z") != "ctx-3-Z") return "FAIL 11: ${ta.call(3, "Z")}"

        val m = Cls::member
        if (m.parameters.size != 1) return "FAIL 12: ${m.parameters.map { it.kind }}"
        if (m.parameters[0].kind != KParameter.Kind.INSTANCE) return "FAIL 13: ${m.parameters[0].kind}"
        if (m.parameters[0].name != null) return "FAIL 14: ${m.parameters[0].name}"
        if (m.call(Cls()) != "ctx-member") return "FAIL 15: ${m.call(Cls())}"
    }

    context("ctx", true) {
        val p2 = ::twoCtxProp
        if (p2.getter.parameters.isNotEmpty()) return "FAIL 16: ${p2.getter.parameters.map { it.kind }}"
        p2.setter.call("V")
        if (p2.getter.call() != "ctx-true-V") return "FAIL 17: ${p2.getter.call()}"
    }

    return "OK"
}
