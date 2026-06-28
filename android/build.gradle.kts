allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Fix for older Flutter plugins (e.g. on_audio_query) that don't declare an
// Android "namespace", which newer Android build tools now require. For any
// such plugin we read the package name from its AndroidManifest and use it as
// the namespace. Uses reflection so we don't need the Android plugin types here.
subprojects {
    val applyNamespaceFix = fix@{
        val android = extensions.findByName("android") ?: return@fix
        val getNamespace = android.javaClass.getMethod("getNamespace")
        if (getNamespace.invoke(android) == null) {
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val pkg = groovy.xml.XmlSlurper()
                    .parse(manifestFile)
                    .getProperty("@package")
                    .toString()
                if (pkg.isNotEmpty()) {
                    android.javaClass
                        .getMethod("setNamespace", String::class.java)
                        .invoke(android, pkg)
                }
            }
        }
    }
    // Projects already evaluated (like :app) can't take afterEvaluate, but they
    // already have a namespace anyway, so handle them directly.
    if (state.executed) applyNamespaceFix() else afterEvaluate { applyNamespaceFix() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
