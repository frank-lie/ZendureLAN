# ZendureLAN Support für FHEM (78_ZendureLAN.pm)

Es handelt sich um ein Modul für FHEM, um die Rest-API von Zendure-Geräten zu nutzen. Die Beschreibung der Rest-API ist hier zu finden: https://github.com/Zendure/zenSDK/blob/main/README.md

## Installation und Verwendung 

1. Damit das Modul in FHEM verwendet werden kann, ist der folgende update-Befehl in FHEM auszuführen:
   
   ```
   update all https://raw.githubusercontent.com/frank-lie/ZendureLAN/main/controls_ZendureLAN.txt
   ```
   Alternativ kann auch die Datei "FHEM/78_ZendureLAN.pm" manuell in den Ordner fhem/FHEM kopiert werden.   
> [!TIP]
> Um automatisch immer die aktuelle Version des Moduls im Rahmen des FHEM-Befehls `update` zu erhalten, kann man den Link auch generell als Update-Quelle hinzufügen:
>```
>update add https://raw.githubusercontent.com/frank-lie/ZendureLAN/main/controls_ZendureLAN.txt
>```

2. Nach einem Update von FHEM sollte in der Regel ein Neustart von FHEM gemacht werden, damit alle Änderungen ordnungsgemäß geladen werden:
   ```
   shutdown restart
   ```   
3. Für die Kommunikation mit dem Zendure-Gerät ist in FHEM zunächst ein Device anzulegen: 
   ```
   define <NAME> ZendureLAN <IP_ADRESS> <SERIENNUMMER>
   ```
   Bei der Seriennummer ist die Seriennummer des Zendure-Gerätes, nicht die Seriennummer der Batterie zu verwenden. Wenn die Seriennummer nicht korrekt angegeben worden sind, können dennoch die Daten des Gerätes über die Rest-API abgerufen werden. Ein Senden von Befehlen ist dann allerdings nicht möglich.

4. Einstellungen

   Über das Attribut interval kann die Aktualisierungszeit in Sekunden individuell angepasst werden. Eine Verringerung des Attributs interval unter 10 ist nicht zulässig, um eine stabile Funktion des Zendure-Gerätes zu gewährleisten. 
  
   
