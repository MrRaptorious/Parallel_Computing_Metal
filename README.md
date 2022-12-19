# Parallel Computing mit der MetalAPI
Projekt mit Metal im Rahmen des WPF "Parallel Computing" an der Hochschule Karlsruhe

Bei dem Projekt handelt es sich um eine "Simulation" (hat nicht wirklich einen Nutzen, außer schön auszusehen) von 50K - 100K "Agents", welche sich auf einer 2d Textur in eine bestimmte Richtung bewegen.

Diese hinterlassen eine Spur, welche über die Zeit verschwimmt (Blur) und zusätzlich in Intensität abnimmt. Ein Agent tastet in jedem Schritt mit 3 Sensoren seine Umgebung ab, um sich präferiert in die Richtung mit den meisten anderen Agents zu begeben.

So entstehen "lebendige" und schön anzusehende Muster wie in den Folgenden Bildern zu sehen ist.

<img width="783" alt="grafik" src="https://user-images.githubusercontent.com/35742529/208477431-1367bf9e-c23c-4cff-aa11-5143f65fb5ab.png">

<img width="781" alt="grafik" src="https://user-images.githubusercontent.com/35742529/208477670-2e94d300-c2ec-4d94-be3f-6d78cff4987b.png">
 
 <img width="789" alt="grafik" src="https://user-images.githubusercontent.com/35742529/208477980-620f7789-3ce1-4669-b878-a814d0aa142d.png">

Als Quellen und Inspiration wurde der Youtube Kanal "Sebastian Legue" (https://www.youtube.com/@SebastianLague) genutzt, der ein sehr ähnliches Projekt entwickelt hat, auf dem dieses auch basiert. Allerdings ist dies in Umfeld einer Unity Anwendung entstanden. Hier lag der Fokus auf Metal als Schnittstelle zum nutzen der GPU. 
