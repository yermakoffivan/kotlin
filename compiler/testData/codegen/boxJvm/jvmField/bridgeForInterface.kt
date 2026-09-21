import kotlin.test.*

open class ValBase(
    @JvmField val foo: String
)

open class VarBase(
    @JvmField var foo: String
)

interface I1 {
    val foo : Any
}

interface I2 {
    val foo : CharSequence
}

interface I3Val {
    val foo : String
}

interface I3Var {
    var foo : String
}

class C1 : ValBase("OK"), I1, I2
class C2 : ValBase("OK"), I1, I2, I3Val
class C3 : VarBase("Fail"), I3Var

fun box(): String {
    run {
        val c: C1 = C1()
        val i1: I1 = c
        val i2: I2 = c
        assertEquals(c.foo, "OK")
        assertEquals(i1.foo, "OK")
        assertEquals(i2.foo, "OK")
    }
    run {
        val c: C2 = C2()
        val i1: I1 = c
        val i2: I2 = c
        val i3: I3Val = c
        assertEquals(c.foo, "OK")
        assertEquals(i1.foo, "OK")
        assertEquals(i2.foo, "OK")
    }
    run {
        val c: C3 = C3()
        val i3: I3Var = c
        i3.foo = "OK"
        assertEquals(c.foo, "OK")
        assertEquals(i3.foo, "OK")
    }
    return "OK"
}
