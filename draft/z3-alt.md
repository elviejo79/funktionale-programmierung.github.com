---
layout: post
description: Wie man schwere algorithmische Probleme automatisch lösen lässt
title: "Harte Nüsse knacken mit Microsoft z3"
author: markus-schlegel
tags: ["Clojure", "z3", "Logische Programmierung", "Erste Schritte", "Projekt"]
---

Ab und zu werden wir als Entwicklerinnen und Entwickler vor knifflige
Aufgaben gestellt, deren Lösungen nach komplizierten, rechenintensiven
Algorithmen verlangen. Unsere spontan entwickelten Algorithmen sind
jedoch meistens ineffizient und finden trotzdem nur Näherungen an die
optimale Lösung. Und wenn sich die Anforderungen leicht ändern, ist
unsere Speziallösung vielleicht hinfällig und wir müssen von Neuem
beginnen. Als Alternative können wir diese Klasse von Problemen in ein
spezielles Format überführen und von sogenannten SAT-Solvern ganz
automatisch lösen lassen. In diesem Artikel zeigen wir anhand eines
kleinen Praxisbeispiels, wie das funktioniert. Wir übersetzen ein
typisches Ressourcenplanungsproblem in das SMT-LIB-2-Format und
schicken dieses dann an das Programm z3. z3 wird von Microsoft
Research entwickelt und ist der derzeit mächtigste SAT-Solver.

<!-- more start -->

## Das Seminarteilnehmerproblem

Seminartag: Anna, Sarah, Martha, Salma und Daisy brauchen jeweils
einen Sitzplatz, aber Anna will nicht neben Sarah sitzen und Martha
und Salma müssen am selben Tisch sitzen. Wir möchten jeder
Seminarteilnehmerin einen Sitzplatz zuordnen und dabei alle Wünsche,
Regeln und sonstigen Einschränkungen beachten.

Wir formulieren das Problem zunächst als Clojure-Programm. Es gibt
Teilnehmerinnen und Doppeltische mit jeweils zwei Sitzplätzen:

```clojure
(defrecord Teilnehmerin [id name])
(defrecord Tisch [id platz-id-links platz-id-rechts])
(defrecord Platz [id])
```

All diese Entitäten sind eindeutig identifizierbar. Eine
Probleminstanz ist zunächst definiert durch eine Menge von
Teilnehmerinnen und eine Menge von Tischen. Wir führen für diese
Mengen neue Wörter ein:

```clojure
;; Eine Menge von Seminarteilnehmerinnen
(defrecord Seminargruppe [teilnehmerinnen])

;; Eine Menge von Tischen
(defrecord Seminarraum [tische])
```

Eine Lösung des Problems besteht aus einer Zuordnung der
Seminarteilnehmerinnen zu den Plätzen an den Tischen im Seminarraum.

```clojure
(defrecord Zuordnung [teilnehmerin-id platz-id])
(defrecord Loesung [zuordungen])
```

Nicht jede Zuordnung entspricht einer korrekten Lösung. "Anna will
nicht neben Sarah sitzen" ist eine Einschränkung an die möglichen
Lösungen. Wie bilden wir solche Einschränkungen ab? Um für zukünftige
Anforderungsänderungen gewappnet zu sein, bedienen wir uns zweier
Tricks der funktionalen Programmierung. 1. Anstatt die Anforderung als
Code in einen Algorithmus zu packen, _reifizieren_
(vergegenständlichen) wir die Anforderung und drücken sie ebenfalls
als Daten aus. 2. Wir sind uns ziemlich sicher, dass Anna und Sarah
nicht die einzigen Spezialfälle bleiben werden. Wir _abstrahieren_
deshalb über die konkret beteiligten Personen.

```clojure
(defrecord Nebensitzerverbot [teilnehmerin-id-1 teilnehmerin-id-2])
```

Wir nennen die Einschränkung ein "Nebensitzerverbot" und
identifizieren die beteiligten Personen, die sich anscheinend nicht
leiden können, über deren eindeutige IDs.

Wir verfahren mit der anderen Einschränkung "Martha und Salma müssen
am selben Tisch sitzen" genauso:

```clojure
(defrecord Nebensitzergebot [teilnehmerin-id-1 teilnehmerin-id-2])
```

Statt "Verbot" haben wir jetzt ein "Gebot".

Eine Probleminstanz besteht jetzt aus einer Seminargruppe (Menge an
Teilnehmerinnen), einem Seminarraum (Menge an Tischen mit Sitzplätzen)
und einer Menge von Regeln, wobei eine Regel entweder ein
Nebensitzerverbot oder ein Nebensitzergebot sein kann.

```clojure
(defrecord Problem [seminargruppe seminarraum regeln])
```

An dieser Stelle ist das Problem umfassend beschrieben und die Lösung
ausreichend charakterisiert. Der klassische nächste Schritt ist jetzt,
dass wir uns einen Algorithmus ausdenken, der diese Probleminstanzen
in Lösungen überführt. Klassischerweise ist das der schwierige Teil
der Aufgabe, denn es gibt keinen von Prinzipien geleiteten Ansatz zur
Entwicklung solcher Algorithmen und die Arbeitsweise ist deshalb
meistens: Ausprobieren und auf spontane Geistesblitze hoffen.

## Das SAT-Problem

Warum tun wir uns so schwer damit, Algorithmen zu finden, die solche
Probleme effizient lösen? Zum Trost sagt uns die Informatik, dass es
nicht an uns Menschen liegt, sondern dass diese Art von Problemen
tatsächlich zu den schwierigen sogenannten _NP-vollständigen_
Problemen gehören.

Wir können uns die Situation bildlich so vorstellen: Die Lösungen
liegen wie Nadeln versteckt in einem Heuhaufen. Der Heuhaufen heißt
auch _Suchraum_. Bei den schwierigen Problemen ist der Suchraum enorm
groß und der Weg vom Startpunkt zum Ziel nicht klar vorgegeben. Eine
Teillösung lässt sich nicht einfach zu einer Gesamtlösung erweitern,
sondern muss unter Umständen wieder komplett verworfen werden. Wer
solche Ressourcenplanungsprobleme schon versucht hat, von Hand zu
lösen, kennt den Effekt. Man denkt, die Lösung ist zum Greifen nah,
aber dann merkt man, dass eine Einschränkung noch keine Beachtung fand
und wir können unsere Teillösung wieder komplett wegwerfen.

Das kanonische NP-vollständige Problem ist das sogenannte
[Erfüllbarkeitsproblem der
Aussagenlogik](https://de.wikipedia.org/wiki/Erfüllbarkeitsproblem_der_Aussagenlogik),
kurz SAT (für engl. Satisfiability). Die Aussagenlogik besteht aus
Variablen, Und-Verknüpfungen, Oder-Verknüpfungen, Negation und den
beiden Wahrheitswerten `true` und `false`. Mit diesen Bausteinen
können wir Ausdrücke formulieren. Ein Ausdruck ohne Variablen kann
direkt einem der Wahrheitswerte zugeordnet werden. Wir können den
Ausdruck sozusagen direkt ausrechnen:

```
   (true oder false) und (false oder (nicht true))
=>       true        und (false oder false)
=>       true        und        false
=>                   false
```

True und true ergibt true, true und false (oder umgekehrt) ergibt
false, false und false ergibt false. True oder true ergibt true, true
oder false (oder umgekehrt) ergibt true, aber false oder false ergibt
false. Nicht true ergibt false, nicht false ergibt true. Wir rechnen
diese logischen Ausdrücke analog zu arithmetischen Ausdrücken von
innen nach außen aus.

Wenn Variablen ins Spiel kommen, können wir den Ausdrücken nicht mehr
einfach Wahrheitswerte zuweisen. Die Wahrheitswerte der Ausdrücke
hängen von den Wahrheitswerten der Variablen ab.

```
   (x oder y) und (x und (nicht z))
```

Wir können uns aber eine ganz zentrale Frage stellen: Gibt es
überhaupt eine Lösung, bei der jeder Variablen ein fester Wahrheitswert
zugeordnet wird und der Gesamtausdruck zu true ausgewertet werden
kann? Und falls ja: welche Wahrheitswerte nehmen dann die Variablen an?

Das Beispiel oben hat mindestens eine gültige Zuordnung. Wenn wir für
x true, für y false und für z false einsetzen, wertet der Ausdruck zu
true aus. Wir nennen diese Zuordnung ein _Modell_ des Ausdrucks. Ein
Modell ist eine Variablenbelegung, die zeigt, dass die Probleminstanz
erfüllbar ist. Deshalb heißt das Problem _Erfüllbarkeitsproblem der
Aussagenlogik_.

In den kleinen Beispielen lassen sich Modelle noch recht einfach
finden. Im Zweifelsfall zählen wir einfach alle Kombinationen von
Wahrheitswertbelegungen für die Variablen auf und rechnen den Ausdruck
jeweils aus. Für drei Variablen gibt es nur 2 hoch 3, also 8 solcher
Kombinationen. Die Zahl der Kombinationen wächst aber exponentiell mit
der Zahl der Variablen. Bei 10 Variablen gibt es schon mehr als 1000
Kombinationen, die wir durchprobieren müssten. Die Menge der
Kombinationen entspricht hier dem Suchraum und der wird schon für
moderate Probleminstanzen enorm groß.

## z3

Wir wollen also davon Abstand nehmen, unser Seminarproblem mit einem
selbst entworfenen Algorithmus zu lösen, weil das Problem nicht
greifbar ist, was daran liegt, dass es sich um eine Form des
SAT-Problems handelt: Wir stehen vor einem riesigen Suchraum, der
exponentiell mit der Größe des Problems wächst.

Das SAT-Problem ist theoretisch zwar ein sehr schwieriges, aber zum
Glück nur im schlimmsten Fall. In der Praxis sind die meisten
konkreten Probleme trotzdem in angemessener Zeit lösbar. Das liegt
daran, dass die SAT-Probleme, die in der Praxis auftreten, doch noch
etwas mehr Struktur enthalten, als das theoretisch allgemeinste
Problem. Forscher haben jahrzehntelang versucht, diese Struktur
auszunutzen, um solche Probleme zu bezwingen. Vor einigen Jahren
erzielte die Wissenschaft den Durchbruch. Die eigentlich schwierigen
Probleme konnten plötzlich in Sekundenschnelle gelöst werden. Im
SAT-Solver z3 von Microsoft Research laufen all diese
wissenschaftlichen Fortschritte zusammen und sind damit auch für
Praktiker nutzbar.

Wir könnten also unser Seminarproblem in ein SAT-Problem übersetzen
und dann z3 die schwierige Arbeit erledigen lassen. Genau das wollen
wir im Folgenden tun. Dazu müssen wir zunächst das Format
kennenlernen, in welchem z3 diese SAT-Probleme entgegennimmt.

## SMT-LIB 2

z3 nimmt SAT-Probleme im speziellen Format [SMT-LIB
2](http://smtlib.cs.uiowa.edu) entgegen. SMT-LIB 2 ist eine
Programmiersprache für SAT-Probleme. Die Programmiersprache ist nicht
imperativ, objektorientiert, oder funktional, sondern sie ist eine
logische Programmiersprache. Ein SMT-LIB-2-Programm teilt sich in zwei
Teile auf: Variablendeklarationen und Assertions. Wir können das oben
beschriebene SAT-Problem in SMT-LIB 2 wie folgt ausdrücken:

```scheme
(declare-const x Bool)
(declare-const y Bool)
(declare-const z Bool)

(assert
  (and
    (or x y)
    (and x (not z))))

(check-sat)
(get-model)
```

In den ersten drei Zeilen deklarieren wir die drei Variablen x, y, und
z. Danach folgt die Assertion, also der Ausdruck, den wir gerne zu
true ausgewertet sehen möchten. In der vorletzten Zeile geben wir die
Anweisung, das Problem auf Erfüllbarkeit zu prüfen. Wenn das Problem
erfüllbar ist, dann gibt es auch ein Modell, also eine
Variablenbelegung, die die Erfüllbarkeit beweist. Dieses Modell lassen
wir uns mit `(get-model)` in der letzten Zeile ausgeben.

z3 kann im Web direkt ausprobiert werden. Wir können unser Programm in
den [Online-Editor](https://rise4fun.com/Z3/) übertragen und von z3
ausführen lassen. Die Ausgabe lautet:

```scheme
sat
(model 
  (define-fun z () Bool
    false)
  (define-fun x () Bool
    true)
)
```

Wir sehen, dass z3 ein Modell gefunden hat. Die Variable z ist in
diesem Modell false und die Variable x ist true. Die Variable y
scheint unerheblich zu sein, darf also sowohl true als auch false
sein. Um diesen Verdacht zu bestätigen, können wir z3 so
konfigurieren, dass es uns immer ein vollständiges Modell ausgibt.
Dazu fügen wir am Anfang des Programms den Ausdruck `(set-option
:model_evaluator.completion true)` hinzu. Um dann einen Ausdruck
auszuwerten, können wir `eval` verwenden. Das ganze Programm sieht
dann so aus:

```scheme
(set-option :model_evaluator.completion true)
(declare-const x Bool)
(declare-const y Bool)
(declare-const z Bool)

(assert
  (and
    (or x y)
    (and x (not z))))

(check-sat)
(eval x)
(eval y)
(eval z)
```

SMT-LIB 2 erlaubt auch die Verwendung von Funktionen. Diese Funktionen
verhalten sich etwas anders als Funktionen in herkömmlichen Sprachen.
In SMT-LIB 2 müssen wir die Funktionen nicht selbst implementieren.
Wir sagen lediglich, dass es eine Funktion gibt und spezifizieren dann
von außen einige Einschränkungen darüber, wie sich die Funktion zu
verhalten hat.

```scheme
(declare-fun f (Bool) Int)

(assert (= 5 (f false)))
(assert (> (f true) 23))

(check-sat)
(get-model)
```

Hier sehen wir, wie mit `declare-fun` eine Funktion deklariert wird.
Wir sagen lediglich, dass die Funktion Bool-Werte (true oder false)
auf Ganzzahlen abbildet. Desweiteren sagen wir, dass die Funktion auf
false angewendet zu 5 auswerten soll. Auf true angewendet soll die
Funktion eine Zahl größer 23 zurückgeben. z3 generiert jetzt für uns
eine Implementierung der Funktion. Die Ausgabe sieht so aus:

```scheme
sat
(model 
  (define-fun f ((x!0 Bool)) Int
    (ite (= x!0 false) 5
    (ite (= x!0 true) 24
      5)))
)
```

z3 hat wieder ein Modell gefunden und uns dabei die Funktion `f`
implementiert. `ite` steht für "if then else". Die Implementierung
sagt, dass die Funktion 5 zurück gibt, wenn die Eingabe false ist.
Wenn die Eingabe true ist, gibt sie 24 zurück.

Mit diesen Werkzeugen können wir jetzt unser eigentliches Problem
mithilfe von z3 lösen.


## Seminarproblem zu z3

Wir möchten unser Seminarproblem nun in SMT-LIB 2 übersetzen, um es
dann von z3 lösen zu lassen. Dazu probieren wir im Online-Editor
zunächst einige Möglichkeiten der Übersetzung aus. Wir konzentrieren
uns als Erstes auf das oben beschriebene konkrete Problem mit fünf
Teilnehmerinnen und zwei Reglen. Erst wenn wir uns später an die
Übersetzung der Clojure-Repräsentation machen, abstrahieren wir und
behandeln dann das allgemeine Problem.


### Die Umgebung

Wir wollen als Erstes die Teilnehmerinnen in SMT-LIB 2 abbilden. Die
Gesamtheit aller Teilnehmerinnen bildet eine Menge. Der entsprechende
Typ ist damit eine geschlossene Aufzählung, ein Enum-Typ. Wir können
Enums in SMT-LIB 2 mit `declare-datatypes` erstellen:

```scheme
(declare-datatypes () ((Teilnehmerin Anna Sarah Martha Salma Daisy)))
```

`Teilnehmerin` ist jetzt ein Typ-Name wie `Integer`. `Anna`, `Sarah`,
`Martha`, `Salma` und `Daisy` sind die Werte, die Variablen dieses
Typen annehmen können. Zu dem Zeitpunkt, wenn wir das SMT-LIB-2-Programm
generieren, müssen wir schon über alle Teilnehmerinnen Bescheid
wissen. Der Datentyp lässt sich nachträglich nicht mehr erweitern.

Es ist möglich, dass mehrere Seminarteilnehmerinnen den selben Namen
haben. Wir sollten deshalb nicht die Namen als Ausprägungen des Typen
`Teilnehmerin` verwenden, sondern die eindeutigen IDs. Seien dazu zum
Zwecke dieses Beispiels die Strings `"id-anna"`, `"id-sarah"`,
`"id-martha"`, `"id-salma"`, `"id-daisy"` die IDs der jeweiligen
Teilnehmerinnen.

```scheme
(declare-datatypes () ((Teilnehmerin id-anna id-sarah id-martha id-salma id-daisy)))
```

Wir übersetzen Tische und Plätze genauso in Enum-Typen:

```scheme
(declare-datatypes () ((Tisch id-tisch-1 id-tisch-2 id-tisch-3)))
(declare-datatypes () ((Platz id-platz-a id-platz-b id-platz-c
                              id-platz-d id-platz-e id-platz-f)))
```

Jetzt fehlt uns noch die Zuordnung von Tischen zu Plätzen. Jeder Tisch
hat einen Platz links und einen Platz rechts. Es gibt mehrere
Möglichkeiten, diesen Zusammenhang zu modellieren. Wir entscheiden uns
dafür, zwei Funktionen einzuführen: `platz-links` und `platz-rechts`,
die jeweils einen Tisch auf einen Platz abbilden.

```scheme
(declare-fun platz-links (Tisch) Platz)
(declare-fun platz-rechts (Tisch) Platz)
```

Wenn wir jetzt keine weiteren Angaben machen, generiert uns z3
automatisch eine Implementierung dieser zwei Funktionen. Das ist in
diesem Fall noch nicht das, was wir wollen. Wir wissen genau, wie sich
die Funktionen zu verhalten haben. Entsprechend müssen wir die
Funktionen in SMT-LIB noch mithilfe einiger Assertions einschränken:

```scheme
(assert (= (platz-links id-tisch-1) id-platz-a))
(assert (= (platz-rechts id-tisch-1) id-platz-b))

(assert (= (platz-links id-tisch-2) id-platz-c))
(assert (= (platz-rechts id-tisch-2) id-platz-d))

(assert (= (platz-links id-tisch-3) id-platz-e))
(assert (= (platz-rechts id-tisch-3) id-platz-f))
```

Zu diesem Zeitpunkt haben wir unsere Modellierung so festgezurrt, dass
z3 gar nichts berechnen muss. Alles ist schon da. Das ist auch richtig
so, denn bisher haben wir nur das Universum beschrieben, innerhalb
dessen wir nun ein Problem lösen möchten.


### Die Beschreibung der Lösung

Die nächste Frage, die wir uns stellen müssen, ist: wie soll eine Lösung
aussehen? Wir rufen uns die Beschreibung der Lösung in Clojure ins
Gedächtnis:

```clojure
(defrecord Zuordnung [teilnehmerin-id platz-id])
(defrecord Loesung [zuordungen])
```

Die Beschreibung ist so noch nicht ganz vollständig, denn nicht jede
Menge von Zuordnungen von Teilnehmerinnen und Sitzplätzen ist eine
gültige Lösung. Diese Einschränkung haben wir bisher implizit im Kopf
mitgeführt. Für z3 müssen wir solche Rahmenbedingungen aber explizit
nennen. Betrachten wir zunächst eine ungültige Lösung:

```clojure
(def ungueltige-loesung
  (Loesung.
    [(Zuordnung. id-anna id-platz-a)
     (Zuordnung. id-anna id-platz-c)]))
```

Die Lösung ist kompletter Unfug. Die Teilnehmerin mit der ID `id-anna`
wird auf Platz `id-platz-a` und auf Platz `id-platz-b` zugewiesen. Das
sollte nicht möglich sein; jede Teilnehmerin darf nur maximal einen
Platz erhalten. Diese Einschränkung können wir durchsetzen, indem wir
die Lösung als Funktion modellieren. Eine Funktion bildet jeden
Eingangswert auf genau einen Ausgangswert ab.

```scheme
(declare-fun loesung (Teilnehmerin) Platz)
```

Das gesamte bisherige Programm sieht damit wie folgt aus.

```scheme
(set-option :model_evaluator.completion true)

(declare-datatypes () ((Teilnehmerin id-anna id-sarah id-martha id-salma id-daisy)))

(declare-datatypes () ((Tisch id-tisch-1 id-tisch-2 id-tisch-3)))
(declare-datatypes () ((Platz id-platz-a id-platz-b id-platz-c
                              id-platz-d id-platz-e id-platz-f)))

(declare-fun platz-links (Tisch) Platz)
(declare-fun platz-rechts (Tisch) Platz)

(assert (= (platz-links id-tisch-1) id-platz-a))
(assert (= (platz-rechts id-tisch-1) id-platz-b))

(assert (= (platz-links id-tisch-2) id-platz-c))
(assert (= (platz-rechts id-tisch-2) id-platz-d))

(assert (= (platz-links id-tisch-3) id-platz-e))
(assert (= (platz-rechts id-tisch-3) id-platz-f))

(declare-fun loesung (Teilnehmerin) Platz)

(check-sat)
(get-model)
(eval (loesung id-anna))
(eval (loesung id-sarah))
(eval (loesung id-martha))
(eval (loesung id-salma))
(eval (loesung id-daisy))
```

Um an die Plätze der fünf Teilnehmerinnen zu gelangen, verwenden wir
ganz am Ende wieder `eval`.

Wir können das so definierte Programm im Online-Editor ausprobieren.
Ein großer Vorteil des Online-Editors ist, dass wir iterativ
modellieren können und so sehr schnell sehen, wo unsere
Spezifikationen noch Lücken haben. In diesem Fall gibt uns z3 direkt
eine unerwünschte "falsche" Lösung. Alle fünf Teilnehmerinnen werden
auf den selben Platz gesetzt! Diese Lösung entspricht jedoch
tatsächlich unserer bisherigen Spezifikation. Wir haben also
vergessen, einige wichtige Angaben zu spezifizieren.

Wir möchten, dass jeder Platz von maximal einer Teilnehmerin besetzt
wird. Die Funktion, die Teilnehmerinnen auf Plätze abbildet, muss also
[injektiv](https://de.wikipedia.org/wiki/Injektive_Funktion) sein. Wir
können die Formel für Injektivität eins zu eins in SMT-LIB 2 ausdrücken.

```scheme
(declare-fun loesung (Teilnehmerin) Platz)

(assert (forall ((t1 Teilnehmerin))
          (forall ((t2 Teilnehmerin))
            (=> (= (loesung t1) (loesung t2))
                (= t1 t2)))))
```

In der Assertion verwenden wir ein neues Konstrukt, den sogenannten
Allquantor `forall`. `forall` nimmt als erstes Argument ein Paar aus
einem frischen Variablennamen und einem Typen und als zweites Argument
einen Ausdruck, worin der neue Variablenname verwendet wird. Der
gesamte, allquantifizierte Ausdruck wird nur dann wahr, wenn der
innere Ausdruck für alle Variablenbelegung wahr ist.

Die Assertion sagt aus, dass zwei Teilnehmerinnen nur dann auf den
selben Platz abgebildet werden dürfen, wenn es sich um ein und
dieselbe Teilnehmerin handelt. Mit diesem Zusatz erhalten wir eine
gültige Lösung von z3.


### Die Regeln

Die Regel "Anna will nicht neben Sarah sitzen" sieht in unserem
Clojure-Programm so aus:

```clojure
;; (defrecord Nebensitzerverbot [teilnehmerin-id-1 teilnehmerin-id-2])
(def regel-1 (Nebensitzerverbot. id-anna id-sarah))
```

Dieses Verbot müssen wir in eine weitere Assertion in dem
SMT-LIB-2-Programm übersetzen. Dazu müssen wir uns klar werden, was
das Verbot genau ausdrückt. Was bedeutet es, nebeneinander zu sitzen?
Zum Zwecke dieses Artikels sagen wir, dass zwei Teilnehmerinnen
nebeneinandersitzen, wenn sie am selben Tisch sitzen. Zwei
Teilnehmerinnen Anna und Sarah sitzen am selben Tisch T, wenn entweder
Anna am linken Platz des Tisches T und Sarah am rechten Platz des
Tisches T sitzt, oder umgekehrt. Es darf also keinen solchen Tisch T
geben. Wir können dafür einen neuen Quantor benutzen, den
Existenzquantor `exists`:

```scheme
(assert (not (exists ((t Tisch))
               (or
                 (and
                   (= (loesung id-anna)
                      (platz-links t))
                   (= (loesung id-sarah)
                      (platz-rechts t)))
                 (and
                   (= (loesung id-anna)
                      (platz-rechts t))
                   (= (loesung id-sarah)
                      (platz-links t)))))))
```

Das Nebensitzergebot mit Martha und Salma sieht ganz ähnlich aus. Der
einzige Unterschied ist, dass das `not` am Anfang entfällt.

```scheme
(assert (exists ((t Tisch))
           (or
             (and
               (= (loesung id-martha)
                  (platz-links t))
               (= (loesing id-salma)
                  (platz-rechts t)))
             (and
               (= (loesung id-martha)
                  (platz-rechts t))
               (= (loesing id-salma)
                  (platz-links t))))))
```

Wenn wir diese zwei Assertions zum Programm hinzufügen, erhalten wir
vom Online-Editor wieder eine Lösung, die dieses Mal allen unseren
Anforderungen genügt.


## Clojure -> SMT-LIB 2

Wir haben gesehen, wie wir ein konkretes Problem in SMT-LIB 2
übersetzen können. Wir möchten jetzt über die konkreten Daten
abstrahieren und beliebige Probleme von einer Clojure-Repräsentation
in SMT-LIB 2 übertragen. Das Format von SMT-LIB 2 basiert, wie wir
gesehen haben, auf S-Expressions. Wir können deshalb auf die
[Standardwerkzeuge von Clojure für
S-Expressions](https://funktionale-programmierung.de/2019/09/17/clojure-macros-2.html)
zurückgreifen und verwenden eine Sequenz von Ausdrücken als
Zwischenrepräsentation des SMT-LIB-2-Programms. Die Sequenz müssen wir
dann nur noch in einen String übersetzen, indem wir die einzelnen
Elemente mit `str` in Strings übersetzen und die Ergebnisse mit
`clojure.string/join` aneinanderketten. Für dieses kleine Programm
sind Syntax-Quote, Quote, Unquote und Unquote-Splicing und die
Sequenz-Zwischenrepräsentation ok, aber in einem komplexer werdenden
Programm sollten wir uns dafür noch geeignetere Abstraktionen
schreiben.

Das grobe Gerüst des Clojure-Programms sieht damit wie folgt aus.

```clojure
(defn seminarraum-platz-ids [seminarraum]
  (mapcat (fn [tisch]
            [(:platz-id-links tisch)
             (:platz-id-rechts tisch)]) (:tische seminarraum)))

(defn problem->list [problem]
  (let [tische (-> problem :seminarraum :tische)
        teilnehmerinnen (-> problem :seminargruppe :teilnehmerinnen)
        plaetze (-> problem :seminarraum seminarraum-platz-ids)
        regeln (:regeln problem)]
    (concat
     prelude

     (declare-teilnehmerinnen teilnehmerinnen)
     (declare-tische tische)
     (declare-plaetze plaetze)

     declare-loesung
     assert-loesung 

     declare-platz-links
     declare-platz-rechts

     (assert-platz-links tische)
     (assert-platz-rechts tische)

     (assert-regeln regeln)

     (postlude teilnehmerinnen)
     )))

(defn problem->smt-lib [problem]
  (clojure.string/join
   "\n" (map str (problem->list problem))))
```

Die einzelnen Teile, die wir hier mit `concat` verknüpfen, müssen wir
jetzt im einzelnen noch implementieren.

Die Teilnehmerinnen, Tische und Plätze übersetzen wir in
`declare-datatypes`.

```clojure
(defn declare-teilnehmerinnen [teilnehmerinnen]
  (let [ids (map (comp symbol :id) teilnehmerinnen)]
    [`(~'declare-datatypes () ((~'Teilnehmerin ~@ids)))]))

(defn declare-tische [tische]
  (let [ids (map (comp symbol :id) tische)]
    [`(~'declare-datatypes () ((~'Tisch ~@ids)))]))

(defn declare-plaetze [platz-ids]
  (let [ids (map symbol platz-ids)]
    [`(~'declare-datatypes () ((~'Platz ~@ids)))]))
```

Die Funktionen für die Zugehörigkeit von Plätzen und Tischen sehen so aus:

```clojure
(def declare-platz-links
  ['(declare-fun platz-links (Tisch) Platz)])

(def declare-platz-rechts
  ['(declare-fun platz-rechts (Tisch) Platz)])

(defn assert-platz-links [tische]
  (map (fn [tisch]
         `(~'assert (~'= (~'platz-links ~(symbol (:id tisch)))
                     ~(symbol (:platz-id-links tisch)))))
       tische))

(defn assert-platz-rechts [tische]
  (map (fn [tisch]
         `(~'assert (~'= (~'platz-rechts ~(symbol (:id tisch)))
                     ~(symbol (:platz-id-rechts tisch)))))
       tische))
```

Für jeden Tisch fügen wir hier pro Funktion eine Assertion hinzu,
welche die Gleichheit der Funktionsanwendung auf die Tisch-ID und der
gegebenen Platz-ID erzwingt.

Die übersetzung einer Regel ist etwas interessanter. Wie wir oben
gesehen haben, sind die Verbots- und Gebotsregel fast gleich zu
übersetzen. Der einzige Unterschied ist, dass bei der Verbotsregel ein
`not` vor den Ausdruck gestellt werden muss. Wir umwickeln diesen
Ausdruck deshalb mit einer Funktion, die das `not` abhängig vom
Regeltypen einführt oder es eben bleiben lässt.

```clojure
(defn assert-regel [regel]
  (let [wrap
        (condp instance? regel
          Nebensitzerverbot
          (fn [x] (list 'not x))
          Nebensitzergebot
          identity)]
    `(~'assert ~(wrap
                 `(~'exists ((~'t ~'Tisch))
                   (~'or
                    (~'and
                     (~'= (~'loesung ~(symbol (:teilnehmerin-id-1 regel)))
                      (~'platz-links ~'t))
                     (~'= (~'loesung ~(symbol (:teilnehmerin-id-2 regel)))
                      (~'platz-rechts ~'t)))
                    (~'and
                     (~'= (~'loesung ~(symbol (:teilnehmerin-id-1 regel)))
                      (~'platz-rechts ~'t))
                     (~'= (~'loesung ~(symbol (:teilnehmerin-id-2 regel)))
                      (~'platz-links ~'t)))))
                 ))))

(defn assert-regeln [regeln]
  (map assert-regel regeln))
```

Am Schluss brauchen wir noch den Aufruf von `check-sat` und die
Auswertung der Lösungsfunktion für die Teilnehmerinnen. Dies ist in
der `postlude`-Funktion implementiert:

```clojure
(defn postlude [teilnehmerinnen]
  (concat
   ['(check-sat)]
   (map (fn [teilnehmerin]
          `(~'eval (~'loesung ~(symbol (.id teilnehmerin)))))
        teilnehmerinnen)))
```

Die Reihenfolge, in der wir hier die `eval`-Ausdrücke anordnen ist
wichtig. Später müssen wir von der Ausgabe von z3 nämlich wieder
rückschließen können, welche Ausgabe welche Teilnehmerin betrifft. Wir
sollten deshalb als Collection für die Teilnehmerinnen einen
Sequenztypen wie `List` oder `Vector` verwenden und beispielsweise von
`Set` Abstand nehmen.

Die übersetzungsfunktion ist damit komplett. Wir sollten jetzt für die
einzelnen Teile noch automatisierte Tests schreiben. Zum Zwecke dieses
Blogartikels reicht es aus, wenn wir die Funktion kurzfristig auf
unser konkretes Problem loslassen und die Ausgabe manuell in den z3
Online-Editor übertragen. Das Ergebnis, was uns z3 gibt, ist
plausibel.

```clojure
sat
platz-id-e
platz-id-c
platz-id-b
platz-id-a
platz-id-f
```

Um `z3` aus dem Clojure-Programm direkt aufrufen zu können, gibt es
mehrere Möglichkeiten des Setups. Am einfachsten ist es, wir
installieren z3 bspw. mithilfe des Nix-Paketmanagers direkt auf
unserem Host-System. Aus Clojure heraus können wir dann einen
z3-Prozess starten, indem wir `clojure.java.shell` verwenden. Der Aufruf sieht so aus:

```clojure
(defn run-z3! [s]
  (clojure.java.shell/sh "z3" "-in" "-t:4000" :in s))
```

Dieser Funktion übergeben wir einen String, der ein SMT-LIB-2-Programm
enthält. Die Funktion ruft dann `z3` in einer Shell auf. Mit `-in`
weisen wir z3 an, das SMT-LIB-2-Programm von der Standardeingabe zu
lesen. Mit `-t:4000` definieren wir einen Timeout von vier Sekunden.
Den String für die Standardeingabe übergeben wir dem `sh`-Befehl mit
dem Keyword-Argument `:in`.

Die Funktion gibt wiederum eine Map mit dem Key `:out` und darunter
einen String -- den Inhalt der Standardausgabe --- zurück. Diese
Ausgabe müssen wir dann nur noch parsen.

```clojure
(defn z3-result->platz-ids [{s :out}]
  (let [lines (clojure.string/split s #"\n")
        platz-ids (drop 1 lines)]
    platz-ids))
```

Die Ausgabe dieser Funktion ist eine Liste von Platz-IDs. Diese müssen
wir jetzt noch mit den ursprünglichen Teilnehmerinnen-IDs verknüpfen
und erhalten so unsere Zuordnungen.

```clojure
(defn solve-problem! [problem]
  (let [platz-ids (-> problem
                      (problem->smt-lib)
                      (run-z3!)
                      (z3-result->platz-ids))

        teilnehmerinnen-ids
        (map :id (-> problem :seminargruppe :teilnehmerinnen))]

      (Loesung.
       (map ->Zuordnung teilnehmerinnen-ids platz-ids))))
```

Und das war's. Wir sollten jetzt noch eine Behandlung des Falls
einbauen, dass das Problem gar keine Lösung hat. Die Ausgabe von
`(check-sat)` ist dann `unsat`.


## Abschließende Gedanken

Wir haben jetzt ein schwieriges Problem in ein SAT-Problem übersetzt
und den allgemeinen Problemlöser z3 darauf angesetzt, das Problem zu
lösen, anstatt uns selbst einen komplizierten Algorithmus auszudenken.
z3 kann solche Probleme erstaunlich schnell lösen, obwohl es sich
theoretisch um die schwierigsten Probleme handelt, die die Informatik
zu bieten hat. Allgemeine Problemlöser wie z3 finden in diesen
Problemen noch genug Struktur, um mithilfe einiger Tricks schnell zu
Ergebnissen zu gelangen. Ist das nicht eigentlich unintuitiv? Die
Struktur, die z3 ausnutzt ist schließlich von Anfang an in der
Probleminstanz enthalten. Durch die Übersetzung in ein SAT-Problem
geht wahrscheinlich sogar noch Struktur verloren. Ist es nicht doch
so, dass wir uns mit dem Wissen über das ursprüngliche Problem selbst
einen viel schnelleren Algorithmus ausdenken könnten?

Theoretisch ist die Antwort auf diese Frage Ja. Aber es verhält sich
hier wahrscheinlich wie bei handoptimiertem Maschinencode. Theoretisch
könnten wir als Programmierer jeden Compiler schlagen, indem wir
Algorithmen ausschließlich in Maschinencode schreiben würden. In der
Praxis sind Optimierungen in modernen Compilern aber so gut, dass sie
in 99% der Fälle besseren Code produzieren können als ein Mensch. Der
Mensch ist viel besser, abstrakt zu denken und den Dschungel an
Informationen so aufzubereiten, dass er für spezialisierte Software
wie z3 überhaupt verständlich wird.

<!-- more end -->