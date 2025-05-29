* DATOS - SISBEN IV

clear all

 cd "/Users/miguelblanco/Library/CloudStorage/OneDrive-Personal/Materias Uniandes/2025 10/Economia Social/Trabajo Final/ES_Trabajo_Final/Código" //Recuerde cambiar el directorio para que todo funcione bien:)


* ----- PRIMERA PARTE ----- *
import delimited "C:\Users\samel\OneDrive\Datos adjuntos\Universidad de los Andes\IV\Econ Social\Trabajo Final\DNP_-_Sisb_n_Personas_20250525.csv", clear

* Colapsamos a nivel hogares en cod_mpio_moda = mode(cod_mpio), by(hogar)
tostring cod_mpio, replace format(%05.0f)
keep cod_mpio grupo llave fex
bysort cod_mpio llave: keep if _n == 1

* Creamos las variables con el número de hogares A o B; y para A-D
gen hogar_AB = inlist(grupo, "A", "B")
gen hogar_AD = inlist(grupo, "A", "B", "C", "D")

* Sumamos por municipio
collapse (sum) hogar_AB hogar_AD, by(cod_mpio)

* Calculamos la proporción A y B sobre total A-D
gen proporcion_AB = hogar_AB / hogar_AD
list cod_mpio hogar_AB hogar_AD proporcion_AB, sep(0) noobs

* Exportamos a Excel
export excel using "tabla_hogares_por_mpio.xlsx", firstrow(variables) replace

* ----- SEGUNDA PARTE ----- *
* Hacemos merge de las bases Población y SISBEN IV
import excel "tabla_hogares_por_mpio.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)  
tempfile hogares
save "hogares"

import excel "hogares_mpio_2022.xlsx", firstrow clear
drop añodeasignación
tostring cod_mpio, replace format(%05.0f) 

* Hacemos el merge
merge 1:1 cod_mpio using "hogares", keep(match) nogenerate

* Calculamos Treatment 
gen treatment = hogar_AB / Hogares

export excel using "tratamiento_base_datos.xlsx", firstrow(variables) replace

* ----- TERCERA PARTE ----- *

import delimited "/Users/miguelblanco/Library/CloudStorage/OneDrive-Personal/Materias Uniandes/2025 10/Economia Social/Trabajo Final/ES_Trabajo_Final/Subsidios_De_Vivienda_Asignados_20250525.csv", clear

* Arreglamos la base de datos (filtramos por MCY y año de asignación 2019 a 2024)
tostring códigodivipolamunicipio, replace format(%05.0f)
keep municipio códigodivipolamunicipio programa estadodepostulación añodeasignación hogares
keep if programa == "MI CASA YA"
keep if estadodepostulación == "Asignados"
keep if inrange(añodeasignación, 2019, 2024)

collapse (sum) hogares, by(municipio códigodivipolamunicipio añodeasignación )

tabulate códigodivipolamunicipio añodeasignación

* --- SOLAMENTE MUNICIPIOS CON TODOS LOS AÑOS ASIGNADOS
* Dejar los municipios que tuvieron asignación antes de 2023
contract códigodivipolamunicipio añodeasignación
bysort códigodivipolamunicipio: gen total_anios = _N
keep if total_anios == 6

* Guardamos lista de municipios con los 6 años
keep códigodivipolamunicipio
duplicates drop
tempfile muni6
save "muni6", replace

* Volvemos a importar la base original de subsidios
import delimited "/Users/miguelblanco/Library/CloudStorage/OneDrive-Personal/Materias Uniandes/2025 10/Economia Social/Trabajo Final/ES_Trabajo_Final/Subsidios_De_Vivienda_Asignados_20250525.csv", clear

* Aseguramos formato de código municipio
tostring códigodivipolamunicipio, replace format(%05.0f)

* Filtramos por programa y estado
keep municipio códigodivipolamunicipio programa estadodepostulación añodeasignación hogares
keep if programa == "MI CASA YA"
keep if estadodepostulación == "Asignados"
keep if inrange(añodeasignación, 2019, 2024)

* Hacemos merge para dejar solo los municipios que tuvieron asignación en todos los 6 años
merge m:1 códigodivipolamunicipio using "muni6", keep(match) nogenerate

* Sumamos el número de subsidios asignados por municipio y año
collapse (sum) hogares, by(municipio códigodivipolamunicipio añodeasignación )
export excel using "subsidios_asignados_por_mpio.xlsx", firstrow(variables) replace


* ----- CUARTA PARTE ----- *
* Vamos a unir tratamiento a la base de datos que tenemos por municipio en años

import excel "tratamiento_base_datos.xlsx", firstrow clear
keep cod_mpio proporcion_AB treatment
tempfile tratamiento
save "tratamiento", replace

import excel "subsidios_asignados_por_mpio.xlsx", firstrow clear
rename códigodivipolamunicipio cod_mpio

merge m:1 cod_mpio using "tratamiento", keep(match) nogenerate
export excel using "base_final_asignados.xlsx", firstrow(variables) replace


* ----- QUINTA PARTE ----- *
* Agregar la población para generar la tasa_subsidio
import excel "base_final_asignados.xlsx", firstrow clear
tempfile poblacion
save "poblacion", replace

import excel "hogares_mpio.xlsx", firstrow clear

merge 1:1 cod_mpio añodeasignación using "poblacion", keep(match) nogenerate
rename Hogares hogares_mpio
rename hogares hogares_subsidio
rename treatment treatment_continuo

gen tasa_subsidio = (hogares_subsidio / hogares_mpio)*1000

* Si se quiere hacer el análisis con un treatment_dummy, solo toma municipios de exposición baja o alta (alta sería tratamiento, baja sería control)
* Calcular percentiles 25 y 75 nacionales de la exposición
summarize treatment_continuo, detail

* Apunta los valores de p25 y p75 que aparecen (o usa lo siguiente para guardarlos):
centile treatment_continuo, centile(25 75)
scalar p25 = r(c_1)
scalar p75 = r(c_2)

* 2. Crear la variable treatment_dummy
gen treatment_dummy = .
replace treatment_dummy = 1 if treatment_continuo > p75
replace treatment_dummy = 0 if treatment_continuo < p25


* ----- REGRESIÓN DEL MODELO ----- *
* Variable que indica post_tratamiento e interacción efecto DiD
gen post = añodeasignación >= 2023
gen did_continuio = post * treatment_continuo
gen did_dummy = post*treatment_dummy

export excel using "base_DiD.xlsx", firstrow(variables) replace

import excel "base_DiD.xlsx", firstrow clear
encode cod_mpio, generate(cod_mpio_num)
xtset cod_mpio_num añodeasignación

xtreg tasa_subsidio did_dummy i.añodeasignación, fe vce(cluster cod_mpio)
xtreg tasa_subsidio post treatment_dummy did_dummy i.añodeasignación, fe vce(cluster cod_mpio)

* ---- AGREGANDO CONTROLES --------- *

*------Numero de personas en ruralidad-----------------
* 1. Importar los datos desde "Table1"
import excel "hogares_mpio_xx.xlsx", sheet("Table1") firstrow clear

* 2. Asegurar nombres correctos y tipos
rename CódigoMunicipio cod_mpio
rename Área area
rename Value poblacion
rename Attribute año
tostring cod_mpio, replace format(%05.0f)
destring año, replace


* 3. Codificamos el área para usar en reshape
encode area, gen(area_id)
keep cod_mpio año area_id poblacion


* 4. Hacemos reshape usando area_id como j()
reshape wide poblacion, i(cod_mpio año) j(area_id)

* 5. Verifica cuál es cuál (consulta la codificación)
label list area_id

* Digamos que:
* area_id==1 corresponde a "Cabecera"
* area_id==2 corresponde a "Centros Poblados y Rural Disperso"
* area_id==3 corresponde a "Total"
* Puedes verificar eso y ajustar si no coinciden

* 6. Crear proporción de ruralidad
gen prop_rural = poblacion2 / poblacion3  // Rural disperso / Total

* 7. Mantener solo lo necesario
keep cod_mpio año prop_rural
rename año añodeasignación
tempfile ruralidad
save "ruralidad", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "ruralidad", keep(match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

*----------Licencias de Construccion ------------*
* 1. Importar el archivo Excel
import excel "Licencias_construccion.xlsx", sheet("elic (2)") firstrow clear

* 2. Verifica nombres de variables
describe

* 3. Filtrar las observaciones de interés
keep if obj_tra == 1 & modalidad == 1 & destino == 1

* 4. Filtrar entre 2018 y 2024
keep if inrange(año, 2018, 2024)

* 5. Contar el número de licencias por municipio y año

collapse (sum) licencia, by(cod_mun año)

* 6.  Renombrar las variables

rename cod_mun cod_mpio
rename año añodeasignación


* 7. Guardar los resultados
tempfile licencias
save "licencias", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "licencias", keep(master match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

*----------Licencias de Construccion vivienda VIS ------------*
* 1. Importar el archivo Excel
import excel "Licencias_construccion.xlsx", sheet("elic (2)") firstrow clear

* 2. Verifica nombres de variables
describe

* 3. Filtrar las observaciones de interés
keep if obj_tra == 1 & modalidad == 1 & destino == 1 & VIS_NVIS == 1
* 4. Filtrar entre 2018 y 2024
keep if inrange(año, 2018, 2024)

* 5. Contar el número de licencias por municipio y año

collapse (sum) licencia, by(cod_mun año)

* 6.  Renombrar las variables

rename cod_mun cod_mpio
rename año añodeasignación
rename licencias licencias_vis


* 7. Guardar los resultados
tempfile licencias_vis
save "licencias_vis", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "licencias_vis", keep(master match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

*----------Licencias de Construccion vivienda VIP ------------*
* 1. Importar el archivo Excel
import excel "Licencias_construccion.xlsx", sheet("elic (2)") firstrow clear

* 2. Verifica nombres de variables
describe

* 3. Filtrar las observaciones de interés
keep if obj_tra == 1 & modalidad == 1 & destino == 1 & VIS_NVIS == 3
* 4. Filtrar entre 2018 y 2024
keep if inrange(año, 2018, 2024)

* 5. Contar el número de licencias por municipio y año

collapse (sum) licencia, by(cod_mun año)

* 6.  Renombrar las variables

rename cod_mun cod_mpio
rename año añodeasignación
rename licencias licencias_vip


* 7. Guardar los resultados
tempfile licencias_vip
save "licencias_vip", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "licencias_vip", keep(master match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

*-------- y con las unidades ------------------*
* 1. Importar el archivo Excel
import excel "Licencias_construccion.xlsx", sheet("elic (2)") firstrow clear

* 2. Verifica nombres de variables
describe

* 3. Filtrar las observaciones de interés
keep if obj_tra == 1 & modalidad == 1 & destino == 1

* 4. Filtrar entre 2018 y 2024
keep if inrange(año, 2018, 2024)

* 5. Contar el número de unidades por municipio y año
collapse (sum) unidades, by(cod_mun año)

* 6.  Renombrar las variables
rename cod_mun cod_mpio
rename año añodeasignación

* 7. Guardar los resultados
tempfile unidades
save "unidades", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "unidades", keep(master match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

*----------Unidades vivienda VIS ------------*
* 1. Importar el archivo Excel
import excel "Licencias_construccion.xlsx", sheet("elic (2)") firstrow clear

* 2. Verifica nombres de variables
describe

* 3. Filtrar las observaciones de interés
keep if obj_tra == 1 & modalidad == 1 & destino == 1 & VIS_NVIS == 1

* 4. Filtrar entre 2018 y 2024
keep if inrange(año, 2018, 2024)

* 5. Contar el número de unidades por municipio y año
collapse (sum) unidades, by(cod_mun año)

* 6.  Renombrar las variables
rename cod_mun cod_mpio
rename año añodeasignación
rename unidades unidades_vis

* 7. Guardar los resultados
tempfile unidades_vis
save "unidades_vis", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "unidades_vis", keep(master match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

*----------Unidades vivienda VIP ------------*
* 1. Importar el archivo Excel
import excel "Licencias_construccion.xlsx", sheet("elic (2)") firstrow clear

* 2. Verifica nombres de variables
describe

* 3. Filtrar las observaciones de interés
keep if obj_tra == 1 & modalidad == 1 & destino == 1 & VIS_NVIS == 3

* 4. Filtrar entre 2018 y 2024
keep if inrange(año, 2018, 2024)

* 5. Contar el número de unidades por municipio y año
collapse (sum) unidades, by(cod_mun año)

* 6.  Renombrar las variables
rename cod_mun cod_mpio
rename año añodeasignación
rename unidades unidades_vip

* 7. Guardar los resultados
tempfile unidades_vip
save "unidades_vip", replace

* 8. Cargar base DiD
import excel "base_DiD.xlsx", firstrow clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* 9. Unir con la base de ruralidad
merge 1:1 cod_mpio añodeasignación using "unidades_vip", keep(master match) nogenerate

* 10. Guardar resultado
export excel using "base_DiD.xlsx", firstrow(variables) replace

* Eliminamos las Missings y las reemplazamos por 0

foreach var in licencias licencias_vip licencias_vis unidades unidades_vis unidades_vip {
    replace `var' = 0 if missing(`var')
}
* Guardamos
export excel using "base_DiD.xlsx", firstrow(variables) replace

*------ REGRESION DE MODELO CON CONTROLES ----------*

import excel "base_DiD.xlsx", firstrow clear // recuerde cambiar el directorio o la ruta para que el modelo corra
encode cod_mpio, generate(cod_mpio_num)
xtset cod_mpio_num añodeasignación

xtreg tasa_subsidio did_dummy i.añodeasignación prop_rural, fe vce(cluster cod_mpio)

xtreg tasa_subsidio did_dummy i.añodeasignación prop_rural licencias, fe vce(cluster cod_mpio)

xtreg tasa_subsidio did_dummy i.añodeasignación prop_rural licencias_vis licencias_vip, fe vce(cluster cod_mpio)

xtreg tasa_subsidio did_dummy i.añodeasignación prop_rural unidades, fe vce(cluster cod_mpio)

xtreg tasa_subsidio did_dummy i.añodeasignación prop_rural unidades_vis unidades_vip, fe vce(cluster cod_mpio)

*---------- TENDENCIAS PARALELAS ---------------------*

* VERISON GRAFICA
* Asegúrate de tener la base con valores originales
use "base_DiD.xlsx", clear
tostring cod_mpio, replace format(%05.0f)
destring añodeasignación, replace

* Calcular promedios por grupo y año
collapse (mean) tasa_subsidio, by(treatment_dummy añodeasignación)

* Graficar con línea vertical en 2023
twoway ///
  (line tasa_subsidio añodeasignación if treatment_dummy==1, sort lcolor(blue) lpattern(solid)) ///
  (line tasa_subsidio añodeasignación if treatment_dummy==0, sort lcolor(red) lpattern(dash)) ///
  , ///
  xline(2023, lpattern(shortdash) lcolor(black)) ///
  legend(label(1 "Tratamiento") label(2 "Control")) ///
  title("Tendencias paralelas: tasa de subsidios") ///
  ytitle("Tasa de subsidios") ///
  xtitle("Año de asignación")


	   
* MODELO PLACEBO CON INTERACCIONES EN AÑOS PRETRATAMIENTO 
* Paso 1: Crear variable placebo: 1 si año >= 2022 y grupo de tratamiento
gen placebo_dummy = (añodeasignación >= 2022 & treatment_dummy == 1)

* Paso 2: Estimar modelo de diferencias en diferencias con placebo
xtreg tasa_subsidio placebo_dummy i.añodeasignación, fe vce(cluster cod_mpio)

* Paso 3: Interpretar el coeficiente de placebo_dummy
* Si el coeficiente es significativo, puede haber violación del supuesto de tendencias paralelas

* ESTUDIO DE EVENTOS 

* Crear variable de tiempo relativo: tratamiento en 2024
replace rel_year = añodeasignación - 2023
replace rel_year2 = rel_year + 4


* Crear dummies de tiempo relativo
tab rel_year2, gen(rel_yr2)

* Estimar modelo de event study
xtreg tasa_subsidio i.rel_year2##i.treatment_dummy, fe vce(cluster cod_mpio)


* Guardar los coeficientes del evento (años relativos)
margins rel_year2#treatment_dummy

* Graficar los efectos relativos del tratamiento
marginsplot, ///
    recast(line) ///
    ciopts(recast(rline)) ///
    xline(4, lpattern(shortdash) lcolor(black)) ///
    title("Estudio de Eventos: efectos relativos del tratamiento") ///
    ytitle("Efecto sobre tasa de subsidio") ///
    xtitle("Años relativos al tratamiento (2023 = año 0)") ///
    legend(off)

