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

subprojects {
    // Belt-and-braces for the Windows "Could not close incremental caches"
    // failure in plugin modules (e.g. :shared_preferences_android applies
    // the kotlin-android plugin itself): force incremental compilation off
    // on every Kotlin compile task, not just via gradle.properties.
    tasks.configureEach {
        if (name.startsWith("compile") && name.endsWith("Kotlin")) {
            runCatching {
                javaClass
                    .getMethod("setIncremental", Boolean::class.javaPrimitiveType)
                    .invoke(this, false)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
