package com.android.smartspaceenabler;

import android.util.Log;

import io.github.libxposed.api.XposedModule;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

public class EnableSmartspaceModule extends XposedModule {

    private static final String TAG = "EnableSmartspace";
    private static final String TARGET_PACKAGE = "com.motorola.launcher3";

    @Override
    public void onModuleLoaded(ModuleLoadedParam param) {
        if (param.isSystemServer()) {
            detach();
            return;
        }
        log(Log.INFO, TAG, "onModuleLoaded: process=" + param.getProcessName());
    }

    @Override
    public void onPackageLoaded(PackageLoadedParam param) {
        if (!TARGET_PACKAGE.equals(param.getPackageName())) {
            return;
        }

        log(Log.INFO, TAG, "onPackageLoaded: " + param.getPackageName());

        // 1. Force QSB_ON_FIRST_SCREEN = true
        try {
            Class<?> featureFlags = Class.forName("com.android.launcher3.config.FeatureFlags");
            Field qsbField = featureFlags.getField("QSB_ON_FIRST_SCREEN");
            qsbField.setBoolean(null, true);
            log(Log.INFO, TAG, "Set QSB_ON_FIRST_SCREEN = true");
        } catch (Throwable t) {
            log(Log.ERROR, TAG, "Failed to set QSB_ON_FIRST_SCREEN: " + t);
        }

        // 2. Hook SmartSpaceFragment.isQsbEnabled() to return true
        try {
            Class<?> fragmentClass = Class.forName(
                    "com.android.launcher3.qsb.SmartspaceQsbWidget$SmartSpaceFragment");
            Method isQsbEnabled = fragmentClass.getDeclaredMethod("isQsbEnabled");

            hook(isQsbEnabled).intercept(chain -> {
                return true;
            });
            log(Log.INFO, TAG, "Hooked SmartSpaceFragment.isQsbEnabled()");
        } catch (Throwable t) {
            log(Log.ERROR, TAG, "Failed to hook isQsbEnabled: " + t);
        }

        // 3. Hook Utilities.isAndroidOne() to return true (safety net)
        try {
            Class<?> utilities = Class.forName("com.android.launcher3.Utilities");
            Method isAndroidOne = utilities.getDeclaredMethod("isAndroidOne", android.content.Context.class);

            hook(isAndroidOne).intercept(chain -> {
                return true;
            });
            log(Log.INFO, TAG, "Hooked Utilities.isAndroidOne()");
        } catch (Throwable t) {
            log(Log.ERROR, TAG, "Failed to hook isAndroidOne: " + t);
        }
    }
}
