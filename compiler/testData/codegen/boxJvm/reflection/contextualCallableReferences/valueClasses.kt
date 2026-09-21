// TARGET_BACKEND: JVM
// WITH_REFLECT
// LANGUAGE: +ContextParameters +CallableReferencesToContextual

import kotlin.test.assertEquals

@JvmInline
value class Z(val value: String)

context(c: String)
fun topLevelValueParam(z: Z): Z = Z(c + z.value)

context(c: String)
fun Z.valueExtension(y: Z): Z = Z(c + value + y.value)

context(c: String)
fun onlyContext(): Z = Z(c)

class A(val a: String) {
    context(c: String)
    fun member(y: Z): Z = Z(a + c + y.value)
}

context(z: Z)
fun valueContext(y: Z): Z = Z(z.value + y.value)

fun box(): String {
    context("X") {
        val f1 = ::topLevelValueParam
        assertEquals(Z("Xz"), f1.call(Z("z")))

        val f2 = Z("r")::valueExtension
        assertEquals(Z("Xry"), f2.call(Z("y")))

        val f3 = ::onlyContext
        assertEquals(Z("X"), f3.call())

        val f4 = A("a")::member
        assertEquals(Z("aXy"), f4.call(Z("y")))

        val f5 = A::member
        assertEquals(Z("aXy"), f5.call(A("a"), Z("y")))
    }

    context(Z("q")) {
        val f6 = ::valueContext
        assertEquals(Z("qy"), f6.call(Z("y")))
    }
    return "OK"
}
