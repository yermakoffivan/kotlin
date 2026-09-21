// LANGUAGE: +ContextParameters
// OPT_IN: kotlin.ExperimentalContextParameters
// TARGET_BACKEND: JVM
// WITH_REFLECT

import kotlin.jvm.internal.Reflection
import kotlin.reflect.KFunction
import kotlin.reflect.KParameter
import kotlin.reflect.full.extensionReceiverParameter
import kotlin.reflect.full.findParameterByName
import kotlin.reflect.full.instanceParameter
import kotlin.reflect.full.valueParameters
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class A {
    context(ctx: String, num: Int)
    fun String.member(arg: Long): String = ctx + num + this + arg
}

context(ctx: String)
fun top(arg: Int): String = ctx + arg

fun box(): String {
    val m = A::class.members.single { it.name == "member" } as KFunction<*>
    assertEquals(
        listOf(
            KParameter.Kind.INSTANCE,
            KParameter.Kind.CONTEXT,
            KParameter.Kind.CONTEXT,
            KParameter.Kind.EXTENSION_RECEIVER,
            KParameter.Kind.VALUE,
        ),
        m.parameters.map { it.kind },
    )
    val ctxParam = m.parameters[1]
    assertEquals("ctx", ctxParam.name)
    assertEquals(1, ctxParam.index)
    assertEquals(String::class, ctxParam.type.classifier)
    assertEquals("num", m.parameters[2].name)
    assertEquals(Int::class, m.parameters[2].type.classifier)
    assertFalse(ctxParam.isOptional)
    assertFalse(ctxParam.isVararg)

    assertEquals(ctxParam, m.findParameterByName("ctx"))
    assertEquals(m.parameters[0], m.instanceParameter)
    assertEquals(m.parameters[3], m.extensionReceiverParameter)
    assertEquals(listOf(m.parameters[4]), m.valueParameters)

    assertEquals("ctx1R2", m.call(A(), "ctx", 1, "R", 2L))

    val members = Reflection.getOrCreateKotlinPackage(object {}::class.java.enclosingClass).members
    val t = members.single { it.name == "top" } as KFunction<*>
    val topCtx = t.parameters[0]
    assertEquals(KParameter.Kind.CONTEXT, topCtx.kind)
    assertEquals("ctx", topCtx.name)
    assertEquals(0, topCtx.index)
    assertEquals(String::class, topCtx.type.classifier)
    assertEquals(topCtx, t.findParameterByName("ctx"))

    return "OK"
}
