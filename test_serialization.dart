import 'package:supanotes/features/notes/data/markdown_serializer.dart';

void main() {
  final markdown = '''
Novo Treino

A1 — Push



*Segunda-feira · Peito, Ombros, Tríceps*

Segunda-feira · Peito, Ombros, Tríceps*

- [ ] Supino reto com halter  
•	7kg  
•	8kg  
•	9kg  
•	Supino inclinado máquina <!-- task:2c33ab56-d5bd-4966-a3d5-519dbe685bf9 -->
•	40,50,60  
  
•	50, 65, 65  
  
•	Desenvolvimento com halter / Máquina de ombro  
  
•	7kg - 8 Rep - Halter  
  
•	9kg  
  
•	Elevação lateral  
  
•	5kg  
  
•	Tríceps corda (polia alta)  
  
•	6.8kg ou 7kg  
  
•	9.1kg  
  
•	Tríceps francês com halter  
  
•	4kg  




B — Pull

Terça-feira · Costas, Bíceps, Ombro posterior



```
•	Puxada pronada            
            
•	25kg            
            
•	31kg            
            
•	Remada máquina            
            
•	Remada unilateral com corda - trocada por remada baixa com triângulo            
            
•	25            
            
•	31kg            
            
•	Máquina voador invertido            
            
•	22kg            
            
•	Rosca máquina (scott)            
            
•	18kg            
            
•	23kg            
            
•	Rosca martelo com halter            
            
•	7kg            
          
        
      
    
  

```



C1 — Pernas (Quad)

*Quarta-feira · Quadríceps, Posterior, Glúteo, Panturrilha*



```
•	Agachamento no Smith            
            
•	10            
            
•	Leg press 45°            
            
•	40            
            
•	Cadeira extensora            
            
•	23            
            
•	29            
            
•	Cadeira Flexora            
            
•	29            
            
•	Mesa flexora            
            
•	25            
            
•	31kg            
            
•	Glúteo kick-back na máquina *(substituindo elevação pélvica)*            
            
•	Panturrilha na máquina            
            
•	20            
            
•	30            
            
•	40            
          
        
      
    
  

```



--- <!-- divider:31078fcb-9232-45c6-94ef-25965c418313|index:1 -->
  
A2 — Push (variação)

*Quinta-feira · Peito, Ombros, Tríceps*



```
•	Supino reto com halter            
            
•	7kg            
            
•	8kg            
            
•	9kg            
            
•	Crossover / Pec deck            
            
•	31kg            
            
•	40kg            
            
•	Desenvolvimento com halter            
            
•	7kg            
            
•	8kg            
            
•	9kg            
            
•	Elevação lateral com halter            
            
•	5kg            
            
•	Tríceps máquina            
            
•	60kg            
            
•	Tríceps francês com halter            
          
        
      
    
  

```



--- <!-- divider:b2092376-f666-42cb-991c-f6c85fea28d3|index:1 -->


## C2 — Pernas (Posterior)



*Sexta-feira · Posterior, Glúteo, Panturrilha*



```
•	Bom dia com anilha            
            
•	Avanço no Smith            
            
•	- Mesa flexora deitado            
            
•	31.8            
            
•	Hip thrust na máquina            
            
•	Panturrilha na máquina sentado            
          
        
      
    
  

```
''';

  final doc = parseNoteToMarkdown(markdown);
  final reserialized = serializeNoteToMarkdown(doc);
  print('=====================');
  print('Original length: \${markdown.length}');
  print('Reserialized length: \${reserialized.length}');
  if (markdown != reserialized) {
    print('DIFFERENCE DETECTED!');
  }
}
