import Foundation

/// 内嵌的品牌图标(base64 PNG)。放在代码里而不是资源包,
/// 避免 xcodegen 平铺 / SPM 资源包 / Bundle.module 三种打包形态的路径差异。
/// Kimi 采用官方 Kimi.Avatar 规格(#000 底 + 白 K + 蓝点,ICON_MULTIPLE 0.6)。
enum BrandIconData {
    private static let openai = Data(base64Encoded:
        "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"
        + "GzZs2LBhLfwD+MNRBKkl4RQAAAAASUVORK5CYII="
    ) ?? Data()

    private static let anthropic = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAY1BMVEX6+fUUFBMAAAD//////vrn5uKko6GzsrAQEA////0YFxbD"
        + "wr8LDAqRkI4GBwVOTUw1NDTY19N7eni5uLVcW1ry8e11dXMcGxo9PTyYl5TPzsuJiIZWVlRoZ2YnJyYiIiFGRUSwQATqAAADDElE"
        + "QVR4nO2Z23aCMBBFJQEEL6j1Sq21//+Vra6lnBMzUCDxafZbwTKTyc6FMJkoiqIoiqIoiqIoiqL0ISWkGxETqHOk9N+o97HCp1ND"
        + "ZM875QmvT2PVwJ4WCWCWzxKkW9NcX6xtnPjpxmD8pDBNIGsKyGwTpwTlmRNIzPYZqFzCPfNRtj1neALYyhvVqilBBgkUJkr8PwUT"
        + "B9DQriq4HkVDR8G3a+gq6Go4ia3hi4KuhufIGr4o6GhIFSpM8ApQH/s1XIMj4TUkyyFQ/QxEo6T6Ca1h5i1AUiSShpn8rCHQTEcl"
        + "mDcafqCGy7Aapti6Clu6kzQM2gfpHBt3XvtrzRpuQ2pov3Ci3eSYjqThKmQJaKmZWfrzHRryYpundod/v0FDUtDsHSUujYafcTTk"
        + "eDftrZPRA/sdRUNW8FZx7hPQMI+i4f51mSENj6hhcz2Yhmn9qhbtTsxno+GBShNGQ+sZXDTkzaHZGEXQkBRcnB7PpKwg2yNen4fQ"
        + "0F6wsY91nod87tcQFooR7MmrRySudUwNuUnNXo9rLWo4vg9s5d/tcmKShsnoPiAFiys8j7sGMg6rISuYw+N4RQIN66Aacjvx6IGH"
        + "57cV/mWkhtzTF2oOT1CNhlyakRraq9yh0is5a3McNR2z0jPL8CIFWSf+0gyABnVyPc4IrA6+C7GGh1ElcA5lHPAevpJnwgjtDSnY"
        + "BUxS0gjtDW30OxMQNRw8FfjOJGQiaEhL7j9KEF7DXvHDa9hLwXsg0JAOzQZq2EvBe6Cz/9BsoIb9FLwHMk1nSwtFD1hBI4I/ks5u"
        + "B2mY0qPr7dTLFidr6ex2kIa08//b4ad+ykxY/Uef3fK7j/yqzYHCnd2ygi37GvY93CcEOnltf8+lQME+IdDJbGsX0mgJ9gnBUbAt"
        + "fbGzRmnICrbXj49FQMPpcA2dVrUbRGsGapgO15AU7E5emg2Hf0JgBbsWsxLfnqqvAJ8Q+ONAp8C0AwvyCaFc42qz66ydpdXpjGe3"
        + "wLpHH2RI399n0o3/x1cURVEURVEURVEURXknvxgRJ5s17RDOAAAAAElFTkSuQmCC"
    ) ?? Data()

    private static let kimi = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAA"
        + "GgAAAAAAAqACAAQAAAABAAAAgKADAAQAAAABAAAAgAAAAABrRiZNAAALyElEQVR4Ae1d6U9UWRY/VUWxCYqIImirDCAaRXHF+MFo"
        + "Mhps98Ql880PE7fEP2C+zRfbf2AiLm0bv+i4mxjjQrvErQ3q6DQuCBhF23ZhUxGKpQrm/q7zbKCL8j2Kqlvv3XMTLKx6de+55/c7"
        + "55577oKLiLrFDxdNNeDWtN/c7f9rgAmgORWYAEwAzTWgeffZAzABNNeA5t1nD8AE0FwDmnefPQATQHMNaN599gBMAM01oHn32QMw"
        + "ATTXgObdZw/ABNBcA5p3nz0AE0BzDWjeffYATADNNaB599kDMAE014Dm3WcPwATQXAOadz9O8/5HvfuuxDSKS88hT0YBUaCT/A1V"
        + "1NVUS10dn8URna6oy8MEiJbKPV7ypGSR57u5lJS/hOLzv6fugI86qi9Qe00Zdb5+QF3Nr4m6/NGSSLbjEv/y0bBIq9ztIW/mdEoq"
        + "/jslTlpBrtRsoXURfkHzAoGultfUXnGUWu78RIG6yqiSwCNE+Gek+697/XHpuZSy6B+UOG09uZIyBPAC9R5m50oYSt7sInK5PNRZ"
        + "94S62z4KlfV4IIIK5FlABJUrq/bEU2LhOvLm/5UoLkVYdxBs8Z4niRKL/kYJOYvIFT8k0lJ9rZ8J8FUVkfnFk5pF3r8sInd8emij"
        + "FiRwJadTgiCKO3lkZIQJUisTIIhSBvMtz7DvRPCXSS63NzQB0Kjw+p4RuWKYSBNsiA400WllMDVqt7q8ycL1x5uW2i2elWRhApjW"
        + "WYw/iImW+RJobaLuTp+IFQLmvxTGk+wBwlDeoH+1u5M6fhf5gNYGUTXPAgZdv7FcocvdRf53ldRZdU4QoD5qosZUJtDtdlNSUhJ5"
        + "PEhPBC+dncJKOjooEIisi4yLi6P4+HjCq9kCmdra2vrIJoYAjALC17qCGbV8r538jbXUdvtf1PFbuUgRt5ttMuznzPcu7KZCVwDw"
        + "s7OzaeHChZSSkkLd3X/Wlsvlordv39KdO3fo9WuRNo1QSUxMpIkTJ1JhYSGlpqYGlaVv05CtoaGB7t69S8+fP//jY3+ryPS9p4BY"
        + "A5AJoJ6uXeT+uztbKVBfTe3//Tf5Ks9Qt6/pj+9G4beYIQCsbdasWbRz504aMWJEv11/8OAB7dixI2IEAPiQY9u2bbRkyRIaMsRc"
        + "UgaEvXfvHv3ww45eBAiIxR5f+U/kTh0t+tQnIPQLT/bhOfl/v0/+j79FNQVsKDhmCAALSkhIkBaHYaC/Au+A5yJRUO/MmTNp+/bt"
        + "tHLlSjkcmWkHrv/Fixd07tx5+vXXil5fCTS/Jd9/DvZ6L5b+EzMEgFJgRV1doZdEgw0Ng6HQ4cOHS4vfsmULzZs3j+AJzJT29nY5"
        + "JO3Zs4fOnj1LTU3RdeFmZAz1TEwRIJSgkfwsLS2Nli5dSgB/7ty5pj0MwC8vL6fS0lJh/efow4cPkRQzInVrT4Bhw4ZRSUmJBL+4"
        + "uFhG/mY0bVi+ncFHP7UmAMCH5W/dulVaPgJRMwXg3759m3bv3k3nz5+3peUb/dSWABjzS0q+uP3iYmtuH+DD8gH+x49Yu7dv0ZIA"
        + "xpgfruXbHXzQVjsC9AR/zpw5psd8ZPgMy7948aLtLd/wWVoRAG5/2bJlMuCbPXu26WjfAH/Xrl104cIF+vTpk6E/279qQwADfLh9"
        + "gG824DPAx5jvNPDBXi0IAPCXL1/+1fKtgH/z5k1Ckgdu30mWb7guxxMgPT2dVqxYQZs3b5Y5fivg37p1S0b7AL+5udnQmaNeHU0A"
        + "WD7AR4YPOX6z4Pt8bfTLL7cIY35ZWZljwQeTHUsAw/Ktg+8juP3S0t30889ljnT7PV2YIwmA5WSs5sHtw/K9XrEj10Tx+Xx04wbA"
        + "/2L5nz+L83oOL44jACwf4MPyZ8yYYRH8G9LtX7p0iXQAH9x2FAEMy7cKfmtrq7D8GzLgA/hODfiCOTPHECAjI4NWr15NmzZtoqKi"
        + "ItOWD/CvXbsmwb98+bI2lm+QwREEgOUDfIz506dPNw0+VvWMqZ6O4DtiCIDlr1q1yjL4sPwv0X4pXblyRTvLd4QHGDlyJK1Zs0a6"
        + "fVi+2S3cAP/q1asywwfwdRrzDeCNV1sOAdgXaIz5cPvTpk0zDT6mesaYDxLoEu0bgPd9tR0BsGMYe/bHjBlDGzdutAQ+Ol9TU0OH"
        + "Dx+WHkB38KEP2xFg9OjRtGHDBrFlO5ny8nJNWz46iwLvgcSQ2eTQl28599+YuSIGgMCykbsPdS4Ae/ezsrLkEIDTRFYLTvqMGjVK"
        + "XMfiovfv38vxP1Jbza3KpuJ523mAcJWUnJxM8+fPlyTIzc2lEydO0P379wmxgY5FOwIAZBw+LSgoIMwicnJy6MiRI3IqCI+gW9GS"
        + "AAbIWDfAtvDx48cTvMHp06epurqacAJZl6I1AQAyjoBh0QhxgeENcNrHibt/gpHadkFgsE6E+x4CwqFDh0ovMGHCBHk+EcOBDtNE"
        + "x3mA+vp6wg8SRfixUnBSCPcTIMeQl5dHp06dooqKCnnpg5V67PSsozxAXV0dnTx5kg4dOkTv3r2TQR5AtTJdRICI4HDSpEnywgrM"
        + "DlCvU2cJjiEAAMeUDjt4sbL39OlTeWYP+wKxWmg18YOLITAcIDiMi/MKr1In4wKn5QwcQQBcGwPw9+7dSw8fPpR39OCoNiJ6XCVj"
        + "WDUul7BSsIkUw0FBwUQ5nGDRCMOLk2YJticAgrXjx49L8B89etTrgia4bdzXAyLgYilE+jgaZmVIwLOYLiJLOW7cOPL7/ZIETgkQ"
        + "bU0AuH2Av2/fPuoLvmHpuL4FHgIkaGxsklfQYEiwes0MposgAIiAVDUuhIKX+daNJoYcsfpqWwK8efOGjh49Rj/+2D/4PZWOk7w1"
        + "NdVUW1sr1wGwqIR1ASsF+w0yMzNlFhHfB7lwJQz2F9i12JIAsPxjx44Jy99Ljx8/7uX2QwGBc34gAJaEsR0M00QEiaHuJexbn5Ez"
        + "wDQRMwXUgWECQwzqBynsVGxHAFgy5ue4ncMK+AYocNmIG6qqquQron3EBlaHBASIuNdw6tRCmjJliswbIGAEITBTaGlpsQUZbEcA"
        + "WPDBgwfl4k041oaI/tmzZ9IjgBxw7cgGWinwBsnJSTI2wKWSOIRiHDtH8GmHCyRslwmE60Z0Hw74BsggAbaHYar48uVLWrt2LU2e"
        + "PNn0GUKjHrwiMMSiEn6QOML1MSBrrBfbEQAKheUNVsGcvrKykvbv3y8Bw24j7BdAbDDQAvkGU8aBymHme7YkgJmOWX0GswrEFrDa"
        + "9evXy5tEYM0DBdIuGUMmQA+mILmDgyIgA4aEdevWiSBvqulbQ3tUZZtfmQB9oEKmD0mjAwcOyPt/MSRghRDZQCcWJkA/qCKQO3Pm"
        + "DL169UoOC7hcCgtDVnIG/VQdU28zAULAgdkGdgdhSEDeAKeQMM1zkjdgAoQgAD7CdBNXweMwyZMnT2jx4sW0YMECOV0EEawsLH2j"
        + "KSUfxxQBoMxvKVTVFAtJnevXr8sp41VxpAxXyuMPS2B38dixY+VfOTFmDKpkHAiDYoYAsDSstcPKkE4NtsoGxSKP39jYOJC+hv0d"
        + "yIR1CKSScaEElpaxKIR1ASSQ8vPz5f4B7Emwy98NQEblz3+cJ2xVWa8A4EKhWG7t74814BkoFnP1WLmbHx4L6wJYWcS6Ag6eYDoJ"
        + "oiBrGeslZghgKApRNoDur8AKg3mH/p7n90NrIOYIEFpc/nSwNWD9dOVgS8D1KdUAE0Cp+tU3zgRQj4FSCZgAStWvvnEmgHoMlErA"
        + "BFCqfvWNMwHUY6BUAiaAUvWrb5wJoB4DpRIwAZSqX33jTAD1GCiVgAmgVP3qG2cCqMdAqQRMAKXqV984E0A9BkolYAIoVb/6xpkA"
        + "6jFQKgETQKn61TfOBFCPgVIJmABK1a++cSaAegyUSsAEUKp+9Y0zAdRjoFQCJoBS9atvnAmgHgOlEjABlKpffeNMAPUYKJWACaBU"
        + "/eobZwKox0CpBEwApepX3zgTQD0GSiVgAihVv/rGmQDqMVAqARNAqfrVN84EUI+BUgmYAErVr77x/wEGNmH8koqC0AAAAABJRU5E"
        + "rkJggg=="
    ) ?? Data()

    private static let xiaomi = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAllBMVEX/////aQD/XwD/ZgD/YgD/4tP/bSD/5tr/wZ7/WQD/VgD/"
        + "+fT/3dD/+PD/zrT/nWv/ilr/ro3/oXn/7eD//vr/bgD/8uj/1MD/eDD/r4T/mGL/j1r/pHX/t4//dRH/gkX/nmX/iEL/2sH/zqz/"
        + "bRP/jlP/fyv/6NX/gD3/1bn/xKj/tJT/4Mn/fUj/kE3/qYb/TAD/kGTtrpFrAAAEKElEQVR4nO2a22KiMBBAJQRLoMquIAiiaFW8"
        + "rNvt/v/PLfcqFDKBofuS0ydb6BxzGSYkk4lEIpFIJBKJpC+O+YDjON8V17TfrvrGDy0rCNYVQWCF/kY/3M8jirgvc/99S1kCITRF"
        + "rUg/EZL+iS73oae56NGdqx8ds5hKN4kMoUoUHmaI0U1tpxiEF/pJgzASeCZS/LeTIhS9gNL1ASO8FjMqHj1XMOLr4Pj+sW/4vBX8"
        + "Yf2g7dmA8ClEeRkQ/zwd8vWLRpj274Y5HR4/mRFG37F4pj3G/lcGyrxXfO2IEz9tg3sfgRij/XPopUduDoeO/0fIXji+hhg+gQlP"
        + "hS1eB6SoK8FOuBqo8ZNO0IXizyLcBkiagAqVKh52/GQUCKWjPb4APQmUKCZBj58g8FTSMXNACfHhAuEYLUBjcHx7hfUUeIKBU4E2"
        + "SnzFAGdDfZQxKDAIdviTMIUG0FzUeBDTVkhC29X1jlQj6CBQ6rfeXlvwvNuvIGbGo4NaXK0t6j05BWYCtzEEtO4bnPvioXqtwjSy"
        + "ifoKE7g30hBHIMGOqpvaBSiwNmw+ivkCk8mC8QWAj+RmIoYIOGUvdAgA5+FGdAzkeIQnQHajCri/VV4LvMMEwkYeKgXcPz8f2dw8"
        + "7SG3bBhPAPY4cqxWgfkHeYaqf73qxrmBI2AG7QLNUpV+3MobXV4LqEuYwFpEQFE/Vz158u0QUEACs1PjadwloJAqvawoRwBWGbsR"
        + "T0AtHze5QDW7Y64AqC61LxwBGi1yrGn2sVr3RRwBheAIVJWN+SO9kq7KO9cER6BZEdYEyk7PBT7H9u4/CVRj25ICUgBJgDsNRxZw"
        + "RxMAZkJuKh5bwFyPJwCJz68H+gvA6gFnPIEtSKCjJhwoAH1F4bdWxUMFgC9s28vyoQIBTKB9ZTRQgIQwgetYAtC14dtoLXCbgLB5"
        + "As8lmcA09CYgnPrLlerFwiH7l9Vb31lNIE8gx1JgUxc4gtaYCdt6LqblUqxoypL8OrVaqOUfa1d/fo+LDRRovqpWi5/y49On8q9q"
        + "y9XVr9fQXdRmIkAB/p5whN2CFPiOwct0nHfF0CHw1foYAeDaOKMxgTCgFlzgPIoAMA1lIG7blqhC27cjTESRHZukMsbfM4Hvl2T4"
        + "2KOAnoTiTxzuiSVBjuAkUIA8CpjQCEjBTUYUWJA/YjPEThDKASVzvCYQ27iu2GCdISDAcryBj9MGzO99ytE3EMYBA28XfoE+6Chb"
        + "CoUuBlrQlsNSItv2O0X1iaMf+6ckcgwRDrlqFuuVElTC3qELAQ72ZtXcCeZEp+QSiqb/DlwvWBqMf6Y2i518daYEc/SjvWc9PK2K"
        + "rfHsMPFT0OxwcXrcWFlFoX7GDl4ws7X5zbf28XZZbN1XqzK63Mb7na97mo15orhL5plvO1sukUgkEolEgs0/6kBRBFgQsBAAAAAA"
        + "SUVORK5CYII="
    ) ?? Data()

    private static let zhipu = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAAAZlBMVEUtLS3///8RERHW1tbMzMzT09MNDQ0nJyfg4OBbW1sAAAAj"
        + "IyMqKiobGxseHh4GBgbu7u6kpKQWFhZhYWH5+flUVFTo6Oiampp8fHyLi4ttbW2rq6u0tLS/v7/GxsaSkpJISEg6OjozfgsIAAAD"
        + "fUlEQVR4nO2b63KjMAyFaS6GmDsUQm5teP+XXGgy2cQYS5GF2c5yfnY06CuO7SNhex8zy1sAFoAFQPvXLFizK8iQAFlepqlYsUuk"
        + "ssyHECpA1sjY9yaSH8tjbQbIZThV9ptCuTcBlKtp0/cqduMAVTJ9fs9LrmMARyf5O4JSD3ASbvJ73mqvA8ikq/yeJ2sNQDPx7/9Z"
        + "4XEI4PIFdK8gGwCcYpcAcT4AKCdb/3TyqwGA0xHoxkAFyFK3ACJQANbOFoGbVlsFYOtgF3gB2CwAC8AvAIiFwHjT2xLuA1HqTocA"
        + "iM9BgHHnl54gLM2hwSF8G+ARAqjqNpGo+DQHZerj+QD2RRcrv4Coq7rVsQEE/SaWNEDU92CvZwNoo24AoAJzPdxquQCa3kjLAIjy"
        + "o6kANv2/VuyBKJ3d5wH4TKJnczOii85q8ACU/eQW+rL7ocEMRANsxx55V73rX604A2GV1mwiAKJqZ1Sb9k9+cvh65YUuP2oviHyj"
        + "fn7ZUQjkD0bMLtduKKFxaoczkBMgPgD5D2PlDg+A3wL5N6PVBg+AVBs+in7WiQkBVifgBZTjBTcHQLgbS3zX2VDsMADAJsRUbjIA"
        + "vG9CeAFgE6JfArkAKCaEFQA0IdHoDGQBAE1IA/QcLQFoJoQRICWZED4AoglhA4BNCPwwGwCyCeECIJsQJgC6CeEBsDAhPACgCYkR"
        + "A2ABYGNCOABAE4L97EIEAE1Ije15EwHsTIg9gKUJsQawNSHWAJROCCcAqRPCCOBfxxLfBZoQSwDQhLz1zeV9AAYTYgVA7YRwAbCY"
        + "EBsAFhNiAQCaEKgMsAQAZyDOhNABLDohLABcJoQKYNUJYQDgMyFEAD4TQgNgNCEkAE4TQgJAdkIwjW0SAK4T4qetubVfDQiQADgT"
        + "klTAQmX6HmMGQH2OAfs13VJNBECZEHCdoAPgOiHyAuYnAuBMCLhO0AFQJgRcJ+gAuE6IXE8FgOuEFN+Y/CQAgTEh4DpBBwgPdWBS"
        + "fexNSPxlDHroTDg/EAqzbntwDETdNeyb/YpjPAvAAuAWYPYjnbMfap39WO/8B5tnP9o9++H22Y/3O50Hf1/ATFc88g8dwOyXXLo6"
        + "w8lMSF4qqVdXfXQwCuK13FFs/Smd+qpXqnS8XF92a9RyV3fdr5KoI9VvSghZIa773VTz3HF8lb7Q+EevfC4AC8D/BPAHa4RHCrR9"
        + "NVoAAAAASUVORK5CYII="
    ) ?? Data()

    static func data(forAsset assetName: String) -> Data? {
        switch assetName {
        case "brand-openai": return openai
        case "brand-anthropic": return anthropic
        case "brand-kimi": return kimi
        case "brand-xiaomi": return xiaomi
        case "brand-zhipu": return zhipu
        default: return nil
        }
    }
}
