# Авторство и сторонние инструменты

Автор AppDock — x0rif0r. Собственный код: MIT, Copyright (c) 2026 x0rif0r (см. LICENSE).

## ipatool — MIT
Автор: Majd Alfhaily и участники проекта.
https://github.com/majd/ipatool
Скачивание из App Store выполняет отдельно установленный CLI; AppDock не содержит его бинарный файл или учётные данные. Текст: Licenses/ipatool-MIT.txt.

## libimobiledevice — LGPL-2.1-or-later
Авторы: команда libimobiledevice, Nikias Bassen, Martin Szulecki и другие участники.
https://github.com/libimobiledevice/libimobiledevice
Отдельно установленные idevice_id, ideviceinfo, idevicescreenshot используются для USB-устройств. Тексты: Licenses/libimobiledevice-LGPL-2.1.txt и libimobiledevice-GPL-2.0.txt.

## ideviceinstaller — GPL-2.0-or-later
Авторы: команда libimobiledevice и участники ideviceinstaller.
https://github.com/libimobiledevice/ideviceinstaller
Отдельно установленный CLI вызывается для установки и списка приложений. Его бинарный файл не включён в AppDock. Текст: Licenses/ideviceinstaller-GPL-2.0.txt.

## DeviceKit — MIT
Copyright (c) 2015 Dennis Weissmann; участники DeviceKit.
https://github.com/devicekit/DeviceKit
Таблица соответствий ProductType и названий iPhone сверена с Device.generated.swift. Сам фреймворк не включён и не используется во время работы. Текст: Licenses/DeviceKit-MIT.txt.

## Платформа и другие приложения
SwiftUI, AppKit, Foundation и CryptoKit предоставляются Apple в составе macOS. iMazing — отдельный продукт DigiDNA; AppDock поддерживает импорт текстового отчёта iMazing, но не содержит его код или лицензию.

Иконки и названия приложений принадлежат их правообладателям. Они читаются из пользовательских IPA; в исходники AppDock и его поставку банковские приложения и их иконки не включаются. Права на сторонние IPA и лицензии Apple ID не передаются лицензией AppDock.

Зависимости внешних CLI поставляются собственными пакетами и сохраняют лицензии своих авторов. AppDock не включает их исходники или бинарные файлы. Локальные помощники для входа и обоев написаны для AppDock и распространяются под MIT.
